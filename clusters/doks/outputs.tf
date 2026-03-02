output "kube_context" {
  value = "doks-benchmark"
}

output "node_count" {
  value = length(module.shared.all_nodes)
}
