# ---------------------------------------------------------------------------
# PodMonitor — Prometheus scrapes Kong metrics on port 8100 (status)
# ---------------------------------------------------------------------------
resource "kubectl_manifest" "pod_monitor" {
  count = var.middlewares.observability.metrics.enabled ? 1 : 0

  yaml_body = yamlencode({
    apiVersion = "monitoring.coreos.com/v1"
    kind       = "PodMonitor"
    metadata = {
      name      = "kong-metrics"
      namespace = var.namespace
      labels = {
        benchmark = "enabled"
      }
    }
    spec = {
      selector = {
        matchLabels = {
          "app.kubernetes.io/name" = "gateway"
          "app.kubernetes.io/instance" = "kong"
        }
      }
      podMetricsEndpoints = [{
        port     = "status"
        path     = "/metrics"
        interval = "15s"
      }]
    }
  })

  depends_on = [helm_release.kong]
}
