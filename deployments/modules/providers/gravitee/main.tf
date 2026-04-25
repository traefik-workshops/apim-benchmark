terraform {
  required_providers {
    kubectl = {
      source  = "alekc/kubectl"
      version = ">= 2.0.4"
    }
  }
}

locals {
  pgsql_name = "gravitee-database"
  pgsql_user = "postgres"
  pgsql_pass = "topsecretpassword"
  pgsql_port = "5432"
  redis_pass = "topsecretpassword"
  redis_port = "6379"

  tolerations = [{
    key      = "node"
    operator = "Equal"
    value    = var.taint
    effect   = "NoSchedule"
  }]
}

resource "kubernetes_namespace_v1" "gravitee" {
  metadata {
    name = var.namespace
  }
}

module "upstream" {
  source        = "../../dependencies/upstream"
  namespace     = var.namespace
  taint         = var.upstream_taint
  service_count = var.service.count

  depends_on = [kubernetes_namespace_v1.gravitee]
}

resource "helm_release" "gravitee" {
  name       = "gravitee"
  repository = "https://helm.gravitee.io"
  chart      = "apim"
  version    = var.chart_version

  namespace = var.namespace
  atomic    = false
  wait      = true
  timeout   = 900

  values = [
    yamlencode({
      # Enable Gravitee's Kubernetes secret provider so the gateway can
      # resolve `secret://kubernetes/<secret-name>` URIs at startup. Used
      # below in gateway.ssl.keystore.secret to load the cert-manager-
      # provisioned TLS material without volume-mounting it. The
      # gateway's ServiceAccount already has secrets:get/list/watch
      # (see chart-template common/role.yaml + apim.roleRules default).
      # Always emit the block so the ternary on .ssl.enabled below flips
      # cleanly without changing the Helm values shape; the secrets
      # plugin sits idle until something resolves a secret:// URI.
      secrets = {
        loadFirst = "kubernetes"
        kubernetes = {
          enabled = var.middlewares.tls.enabled
        }
      }

      # --- Gateway -----------------------------------------------------------
      gateway = {
        apiKey = {
          header = "Authorization"
        }
        image = {
          tag = var.gateway_version
        }
        replicaCount = var.deployment.replica_count
        autoscaling = {
          enabled = false
        }
        type = var.deployment.type
        service = {
          type                  = var.service.type
          externalTrafficPolicy = var.service.external_traffic_policy
        }
        resources = var.deployment.resources != null ? {
          requests = var.deployment.resources.requests
          limits   = var.deployment.resources.limits
        } : null
        deployment = {
          nodeSelector = {
            node = var.taint
          }
          tolerations = local.tolerations
        }
        env = [
          {
            name  = "JAVA_OPTS"
            value = "-Xms256m -Xmx256m -XX:MaxMetaspaceSize=128m -XX:CompressedClassSpaceSize=48m -XX:ReservedCodeCacheSize=32m -XX:+UseStringDeduplication -XX:MaxTenuringThreshold=1 -XX:+ParallelRefProcEnabled -XX:InitiatingHeapOccupancyPercent=25 -Xss256k"
          }
        ]
        services = {
          sync = {
            kubernetes = {
              enabled = true
            }
          }
          # Gravitee APIM does not support OTLP export for metrics, logs, or traces.
          # Internal metrics are disabled since there is no scraping infrastructure.
          metrics = {
            enabled = false
          }
        }
        reporters = {
          elasticsearch = {
            enabled = false
          }
        }
        # TLS termination on the gateway's HTTP listener. Uses the chart's
        # legacy gateway.ssl path (single listener) rather than the newer
        # gateway.servers array — the latter swaps in additional logback
        # boilerplate that conflicts with our minimal config. Same
        # internalPort (8082) becomes HTTPS when ssl.enabled.
        # tlsProtocols pins to TLS 1.3 only; Gravitee/JSSE will then
        # negotiate one of the three TLS 1.3 AEADs with no 1.2 fallback.
        ssl = {
          enabled      = var.middlewares.tls.enabled
          tlsProtocols = "TLSv1.3"
          clientAuth   = "none"
          keystore = {
            type   = "pem"
            secret = "secret://kubernetes/gateway-tls-cert"
            watch  = true
          }
        }
        ratelimit = {
          redis = {
            host     = "gravitee-redis"
            port     = local.redis_port
            password = local.redis_pass
            ssl      = false
          }
        }
      }

      # --- API management -----------------------------------------------------
      api = {
        ingress = {
          management = {
            scheme = "http"
          }
          portal = {
            scheme = "http"
          }
        }
        resources = null
        deployment = {
          nodeSelector = {
            node = var.taint
          }
          tolerations = local.tolerations
        }
        analytics = {
          type = "none"
        }
      }

      # --- UI -----------------------------------------------------------------
      ui = {
        resources = null
        deployment = {
          nodeSelector = {
            node = var.taint
          }
          tolerations = local.tolerations
        }
      }

      # --- Portal -------------------------------------------------------------
      portal = {
        ingress = {
          hosts = ["portal.example.com"]
        }
        resources = null
        deployment = {
          nodeSelector = {
            node = var.taint
          }
          tolerations = local.tolerations
        }
      }

      # --- Database (PostgreSQL via JDBC, no Elasticsearch) -------------------
      management = {
        type = "jdbc"
      }
      jdbc = {
        driver   = "https://jdbc.postgresql.org/download/postgresql-42.2.23.jar"
        url      = "jdbc:postgresql://gravitee-pgsql-postgres:${local.pgsql_port}/${local.pgsql_name}"
        username = local.pgsql_user
        password = local.pgsql_pass
      }

      elasticsearch = {
        enabled = false
      }

      ratelimit = {
        type = "redis"
      }
    })
  ]

  depends_on = [module.redis, module.pgsql, module.upstream]
}

# ---------------------------------------------------------------------------
# Post-apply patch: inject `tlsProtocols: TLSv1.3` into gravitee.yml.
#
# The APIM Helm chart's gateway-configmap template renders the
# http.ssl block with `keystore`, `clientAuth`, `truststore`, `crl`,
# and `sni` -- but *not* `tlsProtocols` (confirmed by grep'ing
# templates/gateway/gateway-configmap.yaml). Setting
# gateway.ssl.tlsProtocols in values is silently dropped. Gravitee
# (Vert.x/JSSE) then falls back to JDK defaults, which accept 1.2+1.3.
#
# Post-apply we read the ConfigMap, inject the line right after the
# `    ssl:` header in gravitee.yml, update the CM, and roll the
# gateway pod so it loads the new config. Idempotent -- the sed only
# inserts when the line is absent.
# ---------------------------------------------------------------------------
resource "null_resource" "gravitee_tls13_patch" {
  count = var.middlewares.tls.enabled ? 1 : 0

  triggers = {
    namespace     = var.namespace
    chart_version = var.chart_version
  }

  provisioner "local-exec" {
    command = <<-EOT
      set -e
      NS="${var.namespace}"
      CM="gravitee-apim-gateway"
      DEPLOY="gravitee-apim-gateway"

      YAML=$(kubectl -n "$NS" get cm "$CM" -o jsonpath='{.data.gravitee\.yml}')
      if printf '%s' "$YAML" | grep -q 'tlsProtocols:'; then
        echo "gravitee.yml already contains tlsProtocols; skipping"
        exit 0
      fi

      PATCHED=$(printf '%s' "$YAML" | python3 -c "
import sys, re
s = sys.stdin.read()
# Insert 'tlsProtocols: TLSv1.3' under the first http.ssl: at 4-space
# indent (the gravitee.yml rendered by the chart puts ssl: at 2 spaces
# under http:, so its children live at 4-space indent).
s = re.sub(r'^(  ssl:\n)', r'\\1    tlsProtocols: TLSv1.3\n', s, count=1, flags=re.MULTILINE)
sys.stdout.write(s)
")

      # Re-render the ConfigMap from the patched yaml and apply it.
      kubectl -n "$NS" create cm "$CM" --from-literal=gravitee.yml="$PATCHED" \
        --dry-run=client -o yaml | kubectl apply -f - >/dev/null

      kubectl -n "$NS" rollout restart deploy/"$DEPLOY"
      kubectl -n "$NS" rollout status deploy/"$DEPLOY" --timeout=180s
    EOT
  }

  depends_on = [helm_release.gravitee]
}
