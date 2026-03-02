output "kube_context" {
  value = "lke-benchmark"
}

output "node_count" {
  value = length(module.shared.all_nodes)
}
