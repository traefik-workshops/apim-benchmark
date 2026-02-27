output "kube_context" {
  value = "k3d-benchmark"
}

output "node_count" {
  value = length(module.shared.all_nodes)
}
