module "upstream" {
  source = "./modules/upstream"

  namespace   = "upstream"
  taint       = var.node_taints.upstream
  deployment  = var.upstream.deployment
  service     = var.upstream.service
  route_count = var.apim_providers_route_count
 
  count = var.upstream.enabled ? 1 : 0
}

module "traefik" {
  source = "./modules/providers/traefik"

  namespace       = "traefik"
  gateway_version = var.apim_providers.traefik.version
  taint           = var.node_taints.traefik
  deployment      = var.apim_providers_deployment
  service         = var.apim_providers_service
  middlewares     = var.apim_providers_middlewares
  route_count     = var.apim_providers_route_count
 
  count = var.apim_providers.traefik.enabled ? 1 : 0
}

