variable "cluster_provider" {
  type        = string
  default     = "k3d"
  description = "Cluster provider"
  validation {
    condition     = contains(["k3d", "aks", "eks", "gke", "lke", "oke", "doks"], var.cluster_provider)
    error_message = "Provider must be one of: k3d, aks, eks, gke, lke, oke, and doks"
  }
}

variable "apim_providers" {
  type        = list(string)
  default     = ["traefik", "upstream"]
  description = "APIM providers"
  validation {
    condition     = length([for p in var.apim_providers : p if contains(["kong", "traefik", "tyk", "gravitee", "envoygateway", "upstream"], p)]) == length(var.apim_providers)
    error_message = "All providers must be one of: kong, traefik, tyk, gravitee, envoygateway, upstream"
  }
}

variable "cluster_location" {
  type        = string
  default     = ""
  description = "Cloud region/zone for the cluster (e.g. us-west-1 for EKS, us-west1-a for GKE)."
}

variable "cluster_node_type" {
  type        = string
  default     = ""
  description = "Default machine type for cluster."
  validation {
    condition     = var.cluster_provider == "k3d" || var.cluster_node_type != ""
    error_message = "cluster_node_type is required for ${var.cluster_provider}"
  }
}

# ---------------------------------------------------------------------------
# Cloud-specific optional variables
# ---------------------------------------------------------------------------
variable "resource_group_name" {
  type        = string
  default     = "benchmark-rg"
  description = "Azure resource group name (AKS only)."
}

variable "compartment_id" {
  type        = string
  default     = ""
  description = "Oracle Cloud compartment ID (OKE only)."
}

variable "apim_provider_node_type" {
  type        = string
  default     = ""
  description = "Machine type for each of the APIM providers, overrides cluster_node_type."
}

variable "upstream_node_type" {
  type        = string
  default     = ""
  description = "Machine type for upstream services, overrides cluster_node_type."
}

variable "loadgen_node_type" {
  type        = string
  default     = ""
  description = "Machine type for load generation, overrides cluster_node_type."
}

variable "dependencies_node_type" {
  type        = string
  default     = ""
  description = "Machine type for dependencies, overrides cluster_node_type."
}

variable "apim_provider_node_count" {
  type        = number
  default     = 1
  description = "Number of nodes for each of the APIM providers."
}

variable "upstream_node_count" {
  type        = number
  default     = 1
  description = "Number of nodes for each of the upstream services."
}

variable "loadgen_node_count" {
  type        = number
  default     = 1
  description = "Number of nodes for each of the load generation."
}

variable "dependencies_node_count" {
  type        = number
  default     = 1
  description = "Number of nodes for the test dependencies."
}
