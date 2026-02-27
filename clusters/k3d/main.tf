module "shared" {
  source = "../shared"

  apim_providers           = var.apim_providers
  apim_provider_node_count = var.apim_provider_node_count
  upstream_node_count      = var.upstream_node_count
  loadgen_node_count       = var.loadgen_node_count
  dependencies_node_count  = var.dependencies_node_count
}

module "k3d" {
  source = "git::https://github.com/traefik-workshops/terraform-demo-modules.git//compute/suse/k3d?ref=main"

  cluster_name = "benchmark"
  worker_nodes = module.shared.all_nodes
}
