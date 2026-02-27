output "cloud_node_count" {
  description = "Total number of nodes for a flat cloud pool."
  value = (
    (length(var.apim_providers) * var.apim_provider_node_count) +
    (length(var.apim_providers) * var.upstream_node_count) +
    (length(var.apim_providers) * var.loadgen_node_count) +
    var.dependencies_node_count
  )
}

output "all_nodes" {
  description = "All node definitions for k3d (taint, label, count)."
  value       = local.all_nodes
}
