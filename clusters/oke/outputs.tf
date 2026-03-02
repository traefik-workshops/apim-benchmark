output "kube_context" {
  value = "oke-benchmark"
}

output "node_count" {
  value = length(module.shared.all_nodes)
}
