# ---------------------------------------------------------------------------
# Dependencies (Grafana, cert-manager, k6-operator, keycloak, otel)
# ---------------------------------------------------------------------------
module "dependencies" {
  source = "./modules/dependencies"

  taint        = var.node_taints.dependencies
  domain       = var.domain
  service_type = var.dependencies_service_type

  dns_traefiker = var.dns_traefiker

  keycloak = {
    enabled = true
    chart   = "/Users/zaidalbirawi/dev/traefik-demo-resources/keycloak/helm"
  }
}

# ---------------------------------------------------------------------------
# Upstream (baseline, no gateway)
# ---------------------------------------------------------------------------
module "upstream" {
  source = "./modules/providers/upstream"

  namespace   = "upstream"
  taint       = var.node_taints.upstream
  deployment  = var.upstream.deployment
  service     = var.upstream.service
  route_count = var.apim_providers_route_count

  count = var.upstream.enabled ? 1 : 0
}

# ---------------------------------------------------------------------------
# Traefik
# ---------------------------------------------------------------------------
module "traefik" {
  source = "./modules/providers/traefik"

  namespace         = "traefik"
  gateway_version   = var.apim_providers.traefik.version
  taint             = var.node_taints.traefik
  upstream_taint    = var.node_taints.traefik-upstream
  loadgen_taint     = var.node_taints.traefik-loadgen
  deployment        = var.apim_providers_deployment
  service           = var.apim_providers_service
  middlewares       = var.apim_providers_middlewares
  route_count       = var.apim_providers_route_count
  traefik_hub_token = var.traefik_hub_token

  count = var.apim_providers.traefik.enabled ? 1 : 0
}

# ---------------------------------------------------------------------------
# Kong
# ---------------------------------------------------------------------------
module "kong" {
  source = "./modules/providers/kong"

  namespace       = "kong"
  gateway_version = var.apim_providers.kong.version
  taint           = var.node_taints.kong
  upstream_taint  = var.node_taints.kong-upstream
  loadgen_taint   = var.node_taints.kong-loadgen
  deployment      = var.apim_providers_deployment
  service         = var.apim_providers_service
  middlewares     = var.apim_providers_middlewares
  route_count     = var.apim_providers_route_count

  count      = var.apim_providers.kong.enabled ? 1 : 0
  depends_on = [module.dependencies]
}

# ---------------------------------------------------------------------------
# Tyk OSS
# ---------------------------------------------------------------------------
module "tyk" {
  source = "./modules/providers/tyk"

  namespace       = "tyk"
  gateway_version = var.apim_providers.tyk.version
  taint           = var.node_taints.tyk
  upstream_taint  = var.node_taints.tyk-upstream
  loadgen_taint   = var.node_taints.tyk-loadgen
  deployment      = var.apim_providers_deployment
  service         = var.apim_providers_service
  middlewares     = var.apim_providers_middlewares
  route_count     = var.apim_providers_route_count

  count      = var.apim_providers.tyk.enabled ? 1 : 0
  depends_on = [module.dependencies]
}

# ---------------------------------------------------------------------------
# Gravitee
# ---------------------------------------------------------------------------
module "gravitee" {
  source = "./modules/providers/gravitee"

  namespace       = "gravitee"
  gateway_version = var.apim_providers.gravitee.version
  taint           = var.node_taints.gravitee
  upstream_taint  = var.node_taints.gravitee-upstream
  loadgen_taint   = var.node_taints.gravitee-loadgen
  deployment      = var.apim_providers_deployment
  service         = var.apim_providers_service
  middlewares     = var.apim_providers_middlewares
  route_count     = var.apim_providers_route_count

  count      = var.apim_providers.gravitee.enabled ? 1 : 0
  depends_on = [module.dependencies]
}

# ---------------------------------------------------------------------------
# Envoy Gateway
# ---------------------------------------------------------------------------
module "envoygateway" {
  source = "./modules/providers/envoygateway"

  namespace       = "envoygateway"
  gateway_version = var.apim_providers.envoygateway.version
  taint           = var.node_taints.envoygateway
  upstream_taint  = var.node_taints.envoygateway-upstream
  loadgen_taint   = var.node_taints.envoygateway-loadgen
  deployment      = var.apim_providers_deployment
  service         = var.apim_providers_service
  middlewares     = var.apim_providers_middlewares
  route_count     = var.apim_providers_route_count

  count      = var.apim_providers.envoygateway.enabled ? 1 : 0
  depends_on = [module.dependencies]
}
