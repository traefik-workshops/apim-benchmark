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

  namespace = var.namespace
  atomic    = false
  wait      = true
  timeout   = 900

  values = [
    yamlencode({
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
        resources = var.deployment.resources.requests.cpu != "0" ? {
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
        # NOTE: Gravitee TLS termination is not configured at the gateway level.
        # The APIM Helm chart's `servers` config requires additional logback
        # resources that conflict with our setup. TLS is handled by external
        # ingress/load-balancer when needed.
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
