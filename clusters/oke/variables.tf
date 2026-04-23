variable "cluster_location" {
  type        = string
  default     = "us-chicago-1"
  description = "OCI region."
}

variable "cluster_node_type" {
  type        = string
  default     = "VM.Standard.E4.Flex"
  description = "OCI compute shape."
}

variable "compartment_id" {
  type        = string
  description = "Oracle Cloud compartment ID."
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
