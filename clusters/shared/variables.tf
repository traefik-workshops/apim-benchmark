variable "apim_providers" {
  type        = list(string)
  description = "APIM providers"
  validation {
    condition     = length([for p in var.apim_providers : p if contains(["kong", "traefik", "tyk", "gravitee", "envoygateway", "upstream"], p)]) == length(var.apim_providers)
    error_message = "All providers must be one of: kong, traefik, tyk, gravitee, envoygateway, upstream"
  }
}

variable "apim_provider_node_count" {
  type        = number
  default     = 1
  description = "Number of nodes per APIM provider gateway."
}

variable "upstream_node_count" {
  type        = number
  default     = 1
  description = "Number of nodes per upstream service."
}

variable "loadgen_node_count" {
  type        = number
  default     = 1
  description = "Number of nodes per load generator."
}

variable "dependencies_node_count" {
  type        = number
  default     = 0
  description = "Number of nodes for shared dependencies. 0 → auto-compute from provider count (1 node per 2 providers, minimum 1). Set explicitly to override."
}
