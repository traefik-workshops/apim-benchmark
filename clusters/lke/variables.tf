variable "linode_token" {
  type        = string
  sensitive   = true
  description = "Linode API token."
}

variable "cluster_location" {
  type        = string
  default     = "us-iad"
  description = "Linode region."
}

variable "cluster_node_type" {
  type        = string
  default     = "g6-dedicated-2"
  description = "Linode instance type."
}

variable "apim_providers" {
  type        = list(string)
  default     = ["traefik", "upstream"]
  description = "APIM providers to benchmark."
}

variable "apim_provider_node_count" {
  type    = number
  default = 1
}

variable "upstream_node_count" {
  type    = number
  default = 1
}

variable "loadgen_node_count" {
  type    = number
  default = 1
}

variable "dependencies_node_count" {
  type    = number
  default = 1
}
