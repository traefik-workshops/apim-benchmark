variable "namespace" {
  type    = string
  default = "dependencies"
}

variable "taint" {
  type = string
}

variable "domain" {
  type        = string
  default     = "benchmarks.demo.traefik.ai"
  description = "Base domain for DNS and ingress."
}

variable "service_type" {
  type        = string
  default     = "ClusterIP"
  description = "Service type for the dependencies Traefik instance."
}

variable "keycloak" {
  type = object({
    enabled = bool
    chart   = string
  })
}
