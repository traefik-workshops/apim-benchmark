output "kube_context" {
  description = "Kubernetes context name for the created cluster."
  value       = var.cluster_provider == "k3d" ? "k3d-benchmark" : "benchmark"
}

output "cluster_provider" {
  description = "The cluster provider used."
  value       = var.cluster_provider
}

output "cloud_node_count" {
  description = "Total number of nodes provisioned (cloud providers only)."
  value       = var.cluster_provider != "k3d" ? local.cloud_node_count : length(local.all_nodes)
}
