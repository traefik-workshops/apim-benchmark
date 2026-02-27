variable "cluster_location" {
  type        = string
  default     = "us-west-2"
  description = "AWS region."
}

variable "cluster_node_type" {
  type        = string
  default     = "m5.xlarge"
  description = "EC2 instance type."
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
