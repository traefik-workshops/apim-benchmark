terraform {
  required_providers {
    kubectl = {
      source  = "alekc/kubectl"
      version = ">= 2.0.4"
    }
  }
}

resource "kubernetes_namespace_v1" "traefik" {
  metadata {
    name = var.namespace
  }
}

module "upstream" {
  source        = "../../dependencies/upstream"
  namespace     = var.namespace
  taint         = var.upstream_taint
  service_count = var.service.count

  depends_on = [kubernetes_namespace_v1.traefik]
}

locals {
  tolerations = [{
    key      = "node"
    operator = "Equal"
    value    = var.taint
    effect   = "NoSchedule"
  }]
}

resource "kubernetes_secret_v1" "traefik_hub_license" {
  count = var.traefik_hub_token != "" ? 1 : 0

  metadata {
    name      = "traefik-hub-license"
    namespace = var.namespace
  }

  type = "Opaque"
  data = {
    token = var.traefik_hub_token
  }

  depends_on = [kubernetes_namespace_v1.traefik]
}

resource "helm_release" "traefik" {
  name       = "traefik"
  repository = "https://traefik.github.io/charts"
  chart      = "traefik"
  version    = "39.0.8"

  namespace = var.namespace
  atomic    = true
  wait      = true
  skip_crds = true

  values = [
    yamlencode(merge({
      image = var.traefik_hub_token != "" ? {
        registry   = "ghcr.io"
        repository = "traefik/traefik-hub"
        tag        = "v3.19.4"
        } : {
        tag = var.gateway_version
      }

      deployment = {
        replicas = var.deployment.replica_count
      }

      ingressRoute = {
        dashboard = {
          enabled = true
        }
      }

      ports = merge({
        traefik = {
          expose = {
            default = true
          }
        }
        }, var.middlewares.tls.enabled ? {
        websecure = {
          expose = {
            default = true
          }
        }
      } : {})

      experimental = merge({
        kubernetesGateway = {
          enabled = true
        }
        }, var.middlewares.observability.logs.enabled ? {
        otlpLogs = true
      } : {})

      gateway = {
        listeners = {
          web = {
            port     = 8000
            protocol = "HTTP"
            namespacePolicy = {
              from = "Same"
            }
          }
        }
      }

      logs = {
        general = {
          level = "INFO"
        }
        access = merge({
          enabled = var.middlewares.observability.logs.enabled
          }, var.middlewares.observability.logs.enabled ? {
          otlp = {
            enabled = true
            http = {
              endpoint = "http://opentelemetry-collector.dependencies.svc:4318/v1/logs"
              tls = {
                insecureSkipVerify = true
              }
            }
          }
        } : {})
      }

      metrics = {
        otlp = {
          enabled              = var.middlewares.observability.metrics.enabled
          addEntryPointsLabels = var.middlewares.observability.metrics.enabled
          addRoutersLabels     = var.middlewares.observability.metrics.enabled
          addServicesLabels    = var.middlewares.observability.metrics.enabled
          http = {
            enabled  = var.middlewares.observability.metrics.enabled
            endpoint = "http://opentelemetry-collector.dependencies.svc:4318/v1/metrics"
            tls = {
              insecureSkipVerify = true
            }
          }
        }
        prometheus = null
      }

      tracing = {
        otlp = {
          enabled = var.middlewares.observability.traces.enabled
          http = {
            enabled  = var.middlewares.observability.traces.enabled
            endpoint = "http://opentelemetry-collector.dependencies.svc:4318/v1/traces"
            tls = {
              insecureSkipVerify = true
            }
          }
        }
      }

      providers = {
        kubernetesCRD = {
          allowCrossNamespace       = false
          allowExternalNameServices = false
          namespaces                = [var.namespace]
        }
        kubernetesIngress = {
          allowExternalNameServices = false
          namespaces                = [var.namespace]
        }
        kubernetesGateway = {
          enabled             = true
          experimentalChannel = false
          namespaces          = [var.namespace]
        }
      }

      ingressClass = {
        enabled        = true
        isDefaultClass = false
        name           = "traefik-benchmark"
      }

      service = {
        type = var.service.type
      }

      resources = var.deployment.resources.requests.cpu != "0" ? {
        requests = var.deployment.resources.requests
        limits   = var.deployment.resources.limits
      } : {}

      tolerations = local.tolerations

      nodeSelector = {
        node = var.taint
      }
      }, var.traefik_hub_token != "" ? {
      hub = {
        token   = "traefik-hub-license"
        offline = true
      }
    } : {}))
  ]

  depends_on = [kubernetes_namespace_v1.traefik, kubernetes_secret_v1.traefik_hub_license]
}
