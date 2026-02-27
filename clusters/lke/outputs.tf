output "kube_context" {
  value = "lke-benchmark"
}

output "node_count" {
  value = module.shared.cloud_node_count
}
