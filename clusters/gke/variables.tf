variable "gcp_project" {
  type        = string
  description = "GCP project ID."
}

variable "gcp_credentials" {
  type        = string
  sensitive   = true
  default     = ""
  description = "Path to GCP service account JSON key. Leave empty to use gcloud auth."
}

variable "cluster_location" {
  type        = string
  default     = "us-west1-a"
  description = "GCP zone."
}

variable "cluster_node_type" {
  type        = string
  default     = "e2-standard-4"
  description = "GCE machine type."
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
