terraform {
  required_providers {
    kubectl = {
      source  = "alekc/kubectl"
      version = ">= 2.0.4"
    }
  }
}

resource "kubernetes_namespace_v1" "tyk" {
  metadata {
    name = var.namespace
  }
}

module "upstream" {
  source        = "../../dependencies/upstream"
  namespace     = var.namespace
  taint         = var.upstream_taint
  service_count = var.service.count

  depends_on = [kubernetes_namespace_v1.tyk]
}

locals {
  tolerations = [{
    key      = "node"
    operator = "Equal"
    value    = var.taint
    effect   = "NoSchedule"
  }]
}

# ---------------------------------------------------------------------------
# Tyk OSS Gateway (no license, no dashboard, no operator)
# ---------------------------------------------------------------------------
resource "helm_release" "tyk" {
  name       = "tyk"
  repository = "https://helm.tyk.io/public/helm/charts"
  chart      = "tyk-oss"
  version    = var.chart_version

  namespace = var.namespace
  atomic    = true
  wait      = true
  timeout   = 300

  values = [
    yamlencode({
      global = merge({
        redis = {
          addrs = ["${local.redis_name}.${var.namespace}.svc:${local.redis_port}"]
          pass  = local.redis_pass
        }
        storageType = "redis"
        components = {
          pump = var.middlewares.observability.metrics.enabled
        }
        }, var.middlewares.tls.enabled ? {
        tls = {
          gateway = true
          # Use the cert-manager-provisioned cert (RSA-2048, shared
          # algorithm parameters with every other gateway in the
          # benchmark) instead of the chart-generated self-signed one.
          useDefaultTykCertificate = false
        }
      } : {})

      # --- Tyk Pump (analytics exporter) -----------------------------------
      # Enabled when observability.metrics is on. Reads analytics from Redis
      # and pushes to the configured backends.
      "tyk-pump" = var.middlewares.observability.metrics.enabled ? {
        pump = {
          backend = ["prometheus"]
          promBackendSettings = {
            listen_address = ":9090"
          }
          nodeSelector = {
            node = var.taint
          }
          tolerations = local.tolerations
          resources   = {}
        }
      } : {}

      "tyk-gateway" = {
        gateway = {
          image = {
            tag = var.gateway_version
          }
          kind         = var.deployment.type
          replicaCount = var.deployment.replica_count
          service = {
            type                  = var.service.type
            externalTrafficPolicy = var.service.external_traffic_policy
          }
          resources = var.deployment.resources != null ? {
            requests = var.deployment.resources.requests
            limits   = var.deployment.resources.limits
          } : {}

          nodeSelector = {
            node = var.taint
          }
          tolerations = local.tolerations

          # Point Tyk at the shared cert-manager secret. The chart auto-
          # mounts it at certificatesMountPath and sets
          # TYK_GW_HTTPSERVEROPTIONS_CERTIFICATES from .tls.certificates.
          # Harmless when global.tls.gateway is false (the chart only
          # consumes it when TLS is enabled).
          tls = {
            secretName            = "gateway-tls-cert"
            certificatesMountPath = "/etc/certs/tyk-gateway"
            certificates = [{
              domain_name = "*"
              cert_file   = "/etc/certs/tyk-gateway/tls.crt"
              key_file    = "/etc/certs/tyk-gateway/tls.key"
            }]
          }

          # The tyk-gateway chart template hardcodes
          #   TYK_GW_HTTPSERVEROPTIONS_MINVERSION=771   (TLS 1.2)
          # with no values-path override, and never emits MAXVERSION.
          # MAXVERSION we can add cleanly via extraEnvs (the chart
          # doesn't emit it, so there's no duplicate); MINVERSION has
          # to be patched post-apply because Kubernetes' strategic
          # merge on the env list dedups by name, keeping the chart's
          # 771 over our extraEnvs 772. The null_resource below does
          # a JSON patch after helm lands. 772 = TLS 1.3.
          extraEnvs = var.middlewares.tls.enabled ? [
            { name = "TYK_GW_HTTPSERVEROPTIONS_MAXVERSION", value = "772" },
          ] : []

          extraVolumes = concat([
            {
              name = "tyk-api-definitions"
              configMap = {
                name = "tyk-api-definitions"
              }
            }
            ],
            local.is_jwt_auth ? [{
              name = "tyk-policies"
              configMap = {
                name = "tyk-policies"
              }
            }] : [],
          )
          extraVolumeMounts = concat([
            {
              name      = "tyk-api-definitions"
              mountPath = "/mnt/tyk-gateway/apps"
              readOnly  = true
            }
            ],
            local.is_jwt_auth ? [{
              name      = "tyk-policies"
              mountPath = "/mnt/tyk-gateway/policies"
              readOnly  = true
            }] : [],
          )

          tykConfig = merge(
            {
              enable_analytics                      = var.middlewares.observability.metrics.enabled
              enable_detailed_recording             = var.middlewares.observability.logs.enabled
              hash_keys                             = false
              enable_jsvm                           = false
              enable_non_transactional_rate_limiter = true
              close_connections                     = false
              max_idle_connections_per_host         = 1000
              app_path                              = "/mnt/tyk-gateway/apps"
            },

            # --- JWT policies file path ------------------------------------------
            local.is_jwt_auth ? {
              policies = {
                policy_source = "file"
                policy_path   = "/mnt/tyk-gateway/policies"
              }
            } : {},

            # --- TLS termination ------------------------------------------------
            # Cert + TLS-listener wiring is in the Helm chart values above
            # (global.tls.gateway + tyk-gateway.gateway.tls). Min/max TLS
            # version is pinned via extraEnvs above -- tykConfig values
            # are no-ops for that setting because the chart hardcodes a
            # MINVERSION env var that takes precedence.

            # --- OpenTelemetry tracing ------------------------------------------
            var.middlewares.observability.traces.enabled ? {
              opentelemetry = {
                enabled  = true
                exporter = "grpc"
                endpoint = "opentelemetry-collector.dependencies.svc:4317"
                sampling = {
                  type = "TraceIDRatioBased"
                  rate = 1
                }
              }
            } : {},
          )
        }
      }
    })
  ]

  depends_on = [
    kubernetes_namespace_v1.tyk,
    module.redis,
    kubernetes_config_map_v1.tyk_api_definitions,
  ]
}

# ---------------------------------------------------------------------------
# Post-apply patch: force TYK_GW_HTTPSERVEROPTIONS_MINVERSION=772 on the
# gateway Deployment's container env. The chart template hardcodes 771
# (TLS 1.2) with no values-path override; strategic merge on the
# container.env list dedups by name, so adding the override via
# extraEnvs loses to the chart's earlier entry. We patch after helm
# applies, using a JSON Patch that targets the specific env entry by
# path (Kubernetes allows this via `kubectl patch --type=json`).
#
# Re-runs on every apply (triggers keyed to chart version + tls flag)
# and on restarts of this null_resource. Idempotent — patching the
# same value is a no-op.
# ---------------------------------------------------------------------------
resource "null_resource" "tyk_min_tls_version_patch" {
  count = var.middlewares.tls.enabled ? 1 : 0

  triggers = {
    namespace     = var.namespace
    chart_version = var.chart_version
    tls_enabled   = tostring(var.middlewares.tls.enabled)
  }

  provisioner "local-exec" {
    command = <<-EOT
      set -e
      kubectl -n ${var.namespace} set env deploy/gateway-tyk-tyk-gateway \
        TYK_GW_HTTPSERVEROPTIONS_MINVERSION=772
      kubectl -n ${var.namespace} rollout status \
        deploy/gateway-tyk-tyk-gateway --timeout=120s
    EOT
  }

  depends_on = [helm_release.tyk]
}
