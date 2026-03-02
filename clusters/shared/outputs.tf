output "all_nodes" {
  description = "Node definitions with taint, label, and count for each role."
  value       = local.all_nodes
}
