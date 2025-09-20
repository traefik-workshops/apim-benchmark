resource "helm_release" "k6-operator" {
  name       = "k6-operator"
  repository = "https://grafana.github.io/helm-charts"
  chart      = "k6-operator"
  version    = "4.0.0"

  namespace = var.namespace
  atomic    = true

  values = [
    yamlencode({
      namespace = {
        create = false
      }
      manager = {
        resources = "null"
      }
      tolerations = local.tolerations
    })
  ]

  depends_on = [kubernetes_namespace.dependencies]
}
