module "shared" {
  source = "../shared"

  apim_providers           = var.apim_providers
  apim_provider_node_count = var.apim_provider_node_count
  upstream_node_count      = var.upstream_node_count
  loadgen_node_count       = var.loadgen_node_count
  dependencies_node_count  = var.dependencies_node_count
}

module "doks" {
  source = "git::https://github.com/traefik-workshops/terraform-demo-modules.git//compute/digitalocean/doks?ref=main"

  cluster_name       = "benchmark"
  cluster_node_type  = var.cluster_node_type
  cluster_node_count = module.shared.cloud_node_count
  cluster_location   = var.cluster_location
}
