resource "kubernetes_namespace" "traefik" {
  metadata {
    name = var.namespace
  }
}

module "traefik" {
  source = "git::https://github.com/traefik-workshops/terraform-demo-modules.git//k8s/traefik?ref=main"
  namespace = "traefik"

  enable_api_gateway    = false
  enable_ai_gateway     = false
  enable_api_management = false
  enable_preview_mode   = false
  enable_offline_mode   = false
  traefik_tag           = var.gateway_version
  deploymentType        = var.deployment.type
  replicaCount          = var.deployment.replica_count
  serviceType           = var.service.type
  resources             = var.deployment.resources
  tolerations           = [{
    key      = "node"
    operator = "Equal"
    value    = var.taint
    effect   = "NoSchedule"
  }]

  depends_on = [kubernetes_namespace.traefik]
}
