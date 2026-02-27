output "kube_context" {
  value = "doks-benchmark"
}

output "node_count" {
  value = module.shared.cloud_node_count
}
