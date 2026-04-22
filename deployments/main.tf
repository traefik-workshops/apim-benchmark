# ---------------------------------------------------------------------------
# Local chart paths — resolved to sibling traefik-demo-resources/ checkout
# when not explicitly overridden (see variables.tf for override hooks).
# ---------------------------------------------------------------------------
locals {
  keycloak_chart_path      = var.keycloak_chart != "" ? var.keycloak_chart : "${path.root}/../../traefik-demo-resources/keycloak/helm"
  dns_traefiker_chart_path = var.dns_traefiker_chart != "" ? var.dns_traefiker_chart : "${path.root}/../../traefik-demo-resources/dns-traefiker/helm"
}

# ---------------------------------------------------------------------------
# Dependencies (Grafana, cert-manager, k6-operator, keycloak, otel)
# ---------------------------------------------------------------------------
module "dependencies" {
  source = "./modules/dependencies"

  taint                 = var.node_taints.dependencies
  domain                = var.domain
  service_type          = var.dependencies_service_type
  traefik_chart_version = local.chart_versions.dep_traefik

  dns_traefiker = {
    enabled     = var.dns_traefiker.enabled
    chart       = local.dns_traefiker_chart_path
    ip_override = var.dns_traefiker.ip_override
  }

  keycloak = {
    enabled = true
    chart   = local.keycloak_chart_path
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
  chart_version     = local.chart_versions.traefik
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
  chart_version   = local.chart_versions.kong
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
  chart_version   = local.chart_versions.tyk
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
  chart_version   = local.chart_versions.gravitee
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
