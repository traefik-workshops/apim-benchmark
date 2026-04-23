locals {
  # Auto-scale dependencies node count with provider count when not explicitly
  # overridden. The deps pool hosts every shared service (Prometheus, Keycloak,
  # OTel Collector, Loki, Tempo, k6-operator, cert-manager, dependencies-
  # Traefik) and absorbs the aggregate load from every provider's test runs.
  # A singleton is fine for 1–2 providers; at 6 providers running in parallel
  # it is the first thing to saturate.
  # Formula: 1 node per 2 providers, minimum 1.
  dependencies_node_count_auto = max(ceil(length(var.apim_providers) / 2), 1)
  dependencies_node_count      = var.dependencies_node_count > 0 ? var.dependencies_node_count : local.dependencies_node_count_auto

  provider_nodes = [
    for provider in var.apim_providers : {
      taint = provider
      label = provider
      count = var.apim_provider_node_count
    } if provider != "upstream"
  ]

  upstream_nodes = [
    for provider in var.apim_providers : {
      taint = provider != "upstream" ? "${provider}-upstream" : "upstream"
      label = provider != "upstream" ? "${provider}-upstream" : "upstream"
      count = var.upstream_node_count
    }
  ]

  loadgen_nodes = [
    for provider in var.apim_providers : {
      taint = "${provider}-loadgen"
      label = "${provider}-loadgen"
      count = var.loadgen_node_count
    }
  ]

  dependencies_node = [{
    taint = ""
    label = "dependencies"
    count = local.dependencies_node_count
  }]

  all_nodes = concat(
    local.dependencies_node,
    local.provider_nodes,
    local.upstream_nodes,
    local.loadgen_nodes
  )
}
