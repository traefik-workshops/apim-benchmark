# ---------------------------------------------------------------------------
# PodMonitor — Prometheus scrapes Traefik metrics on port 9100
# ---------------------------------------------------------------------------
resource "kubectl_manifest" "pod_monitor" {
  count = var.middlewares.observability.metrics.enabled ? 1 : 0

  yaml_body = yamlencode({
    apiVersion = "monitoring.coreos.com/v1"
    kind       = "PodMonitor"
    metadata = {
      name      = "traefik-metrics"
      namespace = var.namespace
      labels = {
        benchmark = "enabled"
      }
    }
    spec = {
      selector = {
        matchLabels = {
          "app.kubernetes.io/name" = "traefik"
        }
      }
      podMetricsEndpoints = [{
        port     = "metrics"
        path     = "/metrics"
        interval = "15s"
      }]
    }
  })

  depends_on = [helm_release.traefik]
}
