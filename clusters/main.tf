locals {
  provider_nodes = [
    for provider in var.apim_providers : {
      taint = provider
      label = ""
      count = var.apim_provider_node_count
    } if provider != "upstream"
  ]

  upstream_nodes = [
    for provider in var.apim_providers : {
      taint = provider != "upstream" ? "${provider}-upstream" : "upstream"
      label = ""
      count = var.upstream_node_count
    } 
  ]

  loadgen_nodes = [
    for provider in var.apim_providers : {
      taint = "${provider}-loadgen"
      label = ""
      count = var.loadgen_node_count
    }
  ]

  dependencies_node = [{
    taint = "dependencies"
      label = ""
    count = var.dependencies_node_count
  }]

  all_nodes = concat(
    local.provider_nodes,
    local.upstream_nodes,
    local.loadgen_nodes,
    local.dependencies_node
  )
}

module "k3d" {
  source = "git::https://github.com/traefik-workshops/terraform-demo-modules.git//clusters/k3d?ref=main"

  cluster_name = "benchmark"
  worker_nodes = local.all_nodes

  count = var.cluster_provider == "k3d" ? 1 : 0
}
