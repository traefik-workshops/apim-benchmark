resource "kubernetes_horizontal_pod_autoscaler_v2" "gravitee-hpa" {
  metadata {
    name      = "gravitee-hpa"
    namespace = var.namespace
  }

  spec {
    min_replicas = var.deployment.replica_count
    max_replicas = var.deployment.hpa.max_replica_count

    scale_target_ref {
      api_version = "apps/v1"
      kind        = var.deployment.type
      name        = "gravitee-apim-gateway"
    }

    metric {
      type = "Resource"
      resource {
        name = "cpu"
        target {
          type                = "Utilization"
          average_utilization = var.deployment.hpa.avg_cpu_util_percentage
        }
      }
    }

    behavior {
      scale_up {
        stabilization_window_seconds = 0
        select_policy                = "Max"
        policy {
          type           = "Pods"
          value          = 1
          period_seconds = 5
        }
      }
    }
  }

  count      = var.deployment.hpa.enabled ? 1 : 0
  depends_on = [helm_release.gravitee]
}
