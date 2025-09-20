resource "helm_release" "cert-manager" {
  name       = "cert-manager"
  repository = "https://charts.jetstack.io"
  chart      = "cert-manager"
  version    = "v1.18.2"

  namespace = var.namespace
  atomic    = true
  
  values = [
    yamlencode({
      installCRDs = true
      tolerations = local.tolerations
      webhook = {
        tolerations = local.tolerations
      }
      cainjector = {
        tolerations = local.tolerations
      }
      startupapicheck = {
        tolerations = local.tolerations
      }
    })
  ]

  depends_on = [kubernetes_namespace.dependencies]
}