variable "azure_subscription_id" {
  type        = string
  sensitive   = true
  default     = ""
  description = "Azure subscription ID. Leave empty to use az CLI auth."
}

variable "cluster_location" {
  type        = string
  default     = "westus2"
  description = "Azure region."
}

variable "cluster_node_type" {
  type        = string
  default     = "Standard_D4s_v3"
  description = "Azure VM size."
}

variable "resource_group_name" {
  type        = string
  default     = "benchmark-rg"
  description = "Azure resource group name."
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
  default = 0
}
