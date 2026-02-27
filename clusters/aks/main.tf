module "shared" {
  source = "../shared"

  apim_providers           = var.apim_providers
  apim_provider_node_count = var.apim_provider_node_count
  upstream_node_count      = var.upstream_node_count
  loadgen_node_count       = var.loadgen_node_count
  dependencies_node_count  = var.dependencies_node_count
}

resource "azurerm_resource_group" "benchmark" {
  name     = var.resource_group_name
  location = var.cluster_location
}

module "aks" {
  source = "git::https://github.com/traefik-workshops/terraform-demo-modules.git//compute/azure/aks?ref=main"

  cluster_name        = "apim-benchmark"
  cluster_node_type   = var.cluster_node_type
  cluster_node_count  = module.shared.cloud_node_count
  cluster_location    = var.cluster_location
  resource_group_name = azurerm_resource_group.benchmark.name
}
