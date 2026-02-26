# ---------------------------------------------------------------------------
# PodMonitor — Prometheus scrapes Gravitee metrics on tech API port 18082
# Requires basic auth (admin:adminadmin) for the technical API endpoint.
# ---------------------------------------------------------------------------
resource "kubernetes_secret" "prometheus_basic_auth" {
  count = var.middlewares.observability.metrics.enabled ? 1 : 0

  metadata {
    name      = "gravitee-metrics-auth"
    namespace = var.namespace
  }

  data = {
    username = "admin"
    password = "adminadmin"
  }

  depends_on = [kubernetes_namespace.gravitee]
}

resource "kubectl_manifest" "pod_monitor" {
  count = var.middlewares.observability.metrics.enabled ? 1 : 0

  yaml_body = yamlencode({
    apiVersion = "monitoring.coreos.com/v1"
    kind       = "PodMonitor"
    metadata = {
      name      = "gravitee-metrics"
      namespace = var.namespace
      labels = {
        benchmark = "enabled"
      }
    }
    spec = {
      selector = {
        matchLabels = {
          "app.kubernetes.io/name"      = "apim"
          "app.kubernetes.io/component" = "gateway"
        }
      }
      podMetricsEndpoints = [{
        port     = "gateway-techapi"
        path     = "/_node/metrics/prometheus"
        interval = "15s"
        basicAuth = {
          username = {
            name = "gravitee-metrics-auth"
            key  = "username"
          }
          password = {
            name = "gravitee-metrics-auth"
            key  = "password"
          }
        }
      }]
    }
  })

  depends_on = [helm_release.gravitee, kubernetes_secret.prometheus_basic_auth]
}
