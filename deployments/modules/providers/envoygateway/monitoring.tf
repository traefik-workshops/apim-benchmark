# ---------------------------------------------------------------------------
# PodMonitor — Prometheus scrapes Envoy proxy metrics on port 19001
# ---------------------------------------------------------------------------
resource "kubectl_manifest" "pod_monitor" {
  count = var.middlewares.observability.metrics.enabled ? 1 : 0

  yaml_body = yamlencode({
    apiVersion = "monitoring.coreos.com/v1"
    kind       = "PodMonitor"
    metadata = {
      name      = "envoy-proxy-metrics"
      namespace = var.namespace
      labels = {
        benchmark = "enabled"
      }
    }
    spec = {
      selector = {
        matchLabels = {
          "gateway.envoyproxy.io/owning-gateway-name" = "envoy-gateway"
        }
      }
      podMetricsEndpoints = [{
        port     = "metrics"
        path     = "/stats/prometheus"
        interval = "15s"
      }]
    }
  })

  depends_on = [kubernetes_service.envoy_proxy]
}
