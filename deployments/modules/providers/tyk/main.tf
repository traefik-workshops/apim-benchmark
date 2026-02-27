terraform {
  required_providers {
    kubectl = {
      source  = "alekc/kubectl"
      version = ">= 2.0.4"
    }
  }
}

resource "kubernetes_namespace" "tyk" {
  metadata {
    name = var.namespace
  }
}

module "upstream" {
  source        = "../../dependencies/upstream"
  namespace     = var.namespace
  taint         = var.upstream_taint
  service_count = var.service.count

  depends_on = [kubernetes_namespace.tyk]
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
          gateway                  = true
          useDefaultTykCertificate = true
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
          resources = var.deployment.resources.requests.cpu != "0" ? {
            requests = var.deployment.resources.requests
            limits   = var.deployment.resources.limits
          } : {}

          nodeSelector = {
            node = var.taint
          }
          tolerations = local.tolerations

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
            # TLS is handled by global.tls.gateway in the Helm chart values.

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
    kubernetes_namespace.tyk,
    module.redis,
    kubernetes_config_map.tyk_api_definitions,
  ]
}
