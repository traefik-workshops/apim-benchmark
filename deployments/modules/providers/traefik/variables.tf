variable "namespace" {
  type = string
}

variable "taint" {
  type = string
}

variable "gateway_version" {
  type = string
}

variable "deployment" {
  type = object({
    type          = string
    replica_count = number
    hpa = object({
      enabled                 = bool
      max_replica_count       = number
      avg_cpu_util_percentage = number
    })
    resources = object({
      requests = object({
        cpu    = string
        memory = string
      })
      limits = object({
        cpu    = string
        memory = string
      })
    })
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

variable "apim_providers_route_count" {
  type        = number
  default     = 1
  description = "Route count for providers."
}

variable "middlewares" {
  type = object({ 
    auth = object({
      enabled   = bool
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
    observability = object({
      logs = object({
        enabled  = bool
        exporter = string
      })
      metrics = object({
        enabled  = bool
        exporter = string
      })
      traces = object({
        enabled  = bool
        exporter = string
        ratio    = string
      })
    })
  })
}