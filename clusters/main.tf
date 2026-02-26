locals {
  # Total node count for cloud clusters — one flat pool, no per-workload isolation
  cloud_node_count = (
    (length(var.apim_providers) * var.apim_provider_node_count) +
    (length(var.apim_providers) * var.upstream_node_count) +
    (length(var.apim_providers) * var.loadgen_node_count) +
    var.dependencies_node_count
  )

  # k3d-specific: individual tainted nodes per workload
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
    taint = "dependencies"
    label = "dependencies"
    count = var.dependencies_node_count
  }]

  all_nodes = concat(
    local.provider_nodes,
    local.upstream_nodes,
    local.loadgen_nodes,
    local.dependencies_node
  )
}

# ---------------------------------------------------------------------------
# k3d — local development cluster with per-workload node isolation
# ---------------------------------------------------------------------------
module "k3d" {
  source = "git::https://github.com/traefik-workshops/terraform-demo-modules.git//compute/suse/k3d?ref=main"

  cluster_name = "benchmark"
  worker_nodes = local.all_nodes

  count = var.cluster_provider == "k3d" ? 1 : 0
}

# ---------------------------------------------------------------------------
# AWS EKS
# ---------------------------------------------------------------------------
module "eks" {
  source = "git::https://github.com/traefik-workshops/terraform-demo-modules.git//compute/aws/eks?ref=main"

  cluster_name       = "benchmark"
  cluster_node_type  = var.cluster_node_type
  cluster_node_count = local.cloud_node_count
  cluster_location   = var.cluster_location

  count = var.cluster_provider == "eks" ? 1 : 0
}

# ---------------------------------------------------------------------------
# Google GKE
# ---------------------------------------------------------------------------
module "gke" {
  source = "git::https://github.com/traefik-workshops/terraform-demo-modules.git//compute/gcp/gke?ref=main"

  cluster_name       = "benchmark"
  cluster_node_type  = var.cluster_node_type
  cluster_node_count = local.cloud_node_count
  cluster_location   = var.cluster_location

  count = var.cluster_provider == "gke" ? 1 : 0
}

# ---------------------------------------------------------------------------
# Azure AKS
# ---------------------------------------------------------------------------
module "aks" {
  source = "git::https://github.com/traefik-workshops/terraform-demo-modules.git//compute/azure/aks?ref=main"

  cluster_name        = "benchmark"
  cluster_node_type   = var.cluster_node_type
  cluster_node_count  = local.cloud_node_count
  cluster_location    = var.cluster_location
  resource_group_name = var.resource_group_name

  count = var.cluster_provider == "aks" ? 1 : 0
}

# ---------------------------------------------------------------------------
# Akamai LKE (Linode Kubernetes Engine)
# ---------------------------------------------------------------------------
module "lke" {
  source = "git::https://github.com/traefik-workshops/terraform-demo-modules.git//compute/akamai/lke?ref=main"

  cluster_name       = "benchmark"
  cluster_node_type  = var.cluster_node_type
  cluster_node_count = local.cloud_node_count
  cluster_location   = var.cluster_location

  count = var.cluster_provider == "lke" ? 1 : 0
}

# ---------------------------------------------------------------------------
# Oracle OKE
# ---------------------------------------------------------------------------
module "oke" {
  source = "git::https://github.com/traefik-workshops/terraform-demo-modules.git//compute/oracle/oke?ref=main"

  cluster_name       = "benchmark"
  cluster_node_type  = var.cluster_node_type
  cluster_node_count = local.cloud_node_count
  cluster_location   = var.cluster_location
  compartment_id     = var.compartment_id

  count = var.cluster_provider == "oke" ? 1 : 0
}

# ---------------------------------------------------------------------------
# DigitalOcean DOKS
# ---------------------------------------------------------------------------
module "doks" {
  source = "git::https://github.com/traefik-workshops/terraform-demo-modules.git//compute/digitalocean/doks?ref=main"

  cluster_name       = "benchmark"
  cluster_node_type  = var.cluster_node_type
  cluster_node_count = local.cloud_node_count
  cluster_location   = var.cluster_location

  count = var.cluster_provider == "doks" ? 1 : 0
}
