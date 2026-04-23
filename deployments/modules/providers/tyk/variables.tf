variable "namespace" {
  type    = string
  default = "tyk"
}

variable "taint" {
  type = string
}

variable "upstream_taint" {
  type = string
}

variable "loadgen_taint" {
  type = string
}

variable "gateway_version" {
  type = string
}

variable "chart_version" {
  type        = string
  description = "Tyk OSS Helm chart version."
}

variable "deployment" {
  type = object({
    type          = string
    replica_count = number
    # null means "no resources configured" — provider should not emit a
    # resources block, or should emit explicit-null overrides to strip
    # chart defaults (see envoygateway). Populate to set requests/limits.
    resources = optional(object({
      requests = object({
        cpu    = string
        memory = string
      })
      limits = object({
        cpu    = string
        memory = string
      })
    }))
  })
}

variable "service" {
  type = object({
    type                    = string
    count                   = number
    external_traffic_policy = string
  })
}

variable "route_count" {
  type = number
}

variable "middlewares" {
  type = object({
    auth = object({
      type      = string
      app_count = number
    })
    quota = object({
      enabled = bool
      rate    = number
      per     = number
    })
    rate_limit = object({
      enabled = bool
      rate    = number
      per     = number
    })
    tls = object({
      enabled = bool
    })
    headers = object({
      request = object({
        set    = map(string)
        remove = list(string)
      })
      response = object({
        set    = map(string)
        remove = list(string)
      })
    })
    observability = object({
      metrics = object({ enabled = bool })
      logs    = object({ enabled = bool })
      traces  = object({ enabled = bool })
    })
  })
}
