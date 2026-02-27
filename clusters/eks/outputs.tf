output "kube_context" {
  value = "benchmark"
}

output "node_count" {
  value = module.shared.cloud_node_count
}
