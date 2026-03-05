locals {
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
    count = var.dependencies_node_count
  }]

  all_nodes = concat(
    local.dependencies_node,
    local.provider_nodes,
    local.upstream_nodes,
    local.loadgen_nodes
  )
}
