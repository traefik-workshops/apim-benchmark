variable "cluster_location" {
  type        = string
  default     = "nyc3"
  description = "DigitalOcean region."
}

variable "cluster_node_type" {
  type        = string
  default     = "s-4vcpu-8gb"
  description = "DigitalOcean droplet size."
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
