output "kube_context" {
  value = "oke-benchmark"
}

output "node_count" {
  value = module.shared.cloud_node_count
}
