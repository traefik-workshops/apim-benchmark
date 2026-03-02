output "kube_context" {
  value = "benchmark"
}

output "node_count" {
  value = length(module.shared.all_nodes)
}
