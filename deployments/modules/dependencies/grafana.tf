module "grafana" {
  source = "/Users/zaidalbirawi/dev/terraform-demo-modules/k8s/observability/grafana"

  namespace = var.namespace

  prometheus = {
    enabled = true
    url = {
      service   = "prometheus-kube-prometheus-prometheus"
      port      = 9090
      namespace = ""
      override  = ""
    }
  }

  tempo = {
    enabled = true
    url = {
      service   = "tempo"
      port      = 3200
      namespace = ""
      override  = ""
    }
  }

  loki = {
    enabled = true
    url = {
      service   = "loki"
      port      = 3100
      namespace = ""
      override  = ""
    }
  }

  extra_values = {
    service = {
      type = var.grafana.service.type
    }
    dashboardProviders = {
      "dashboardproviders.yaml" = {
        apiVersion = 1
        providers = [{
          name = "APIM Benchmarks"
          orgId = 1
          type = "file"
          disableDeletion = false
          editable = true
          updateIntervalSeconds = 10
          options = {
            path = "/var/lib/grafana/dashboards/apim"
          }
        }]
      }
    }
    extraConfigmapMounts = [
      {
        name = "grafana-dashboards"
        mountPath = "/var/lib/grafana/dashboards/apim/dashboards.json"
        subPath = "dashboards.json"
        configMap = "grafana-dashboards-configmap"
        readOnly = true
      }
    ]
    tolerations = local.tolerations
    imageRenderer = {
      tolerations = local.tolerations
    }
  }

  depends_on = [kubernetes_namespace.dependencies, kubernetes_config_map.grafana-dashboard]
}
