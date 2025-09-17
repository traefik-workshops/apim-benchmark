variable "kubernetes_config_path" {
  type        = string
  default     = "~/.kube/config"
  description = "Kubernetes config file path."
}

variable "kubernetes_config_context" {
  type        = string
  default     = "k3d-benchmark"
  description = "Kubernetes config context."
}

variable "upstream" {
  type = object({
    enabled = bool
    deployment = object({
      type          = string
      replica_count = number
    })
    service = object({
      type                    = string
      count                   = number
      external_traffic_policy = string
    })
  })

  default = {
    enabled = true
    deployment = {
      type          = "Deployment"
      replica_count = 1
    }
    service = {
      type                    = "ClusterIP"
      count                   = 1
      external_traffic_policy = "Local"
    }
  }

  description = "The upstream configuration."
}

variable "apim_providers" {
  type = object({
    gravitee = object({
      enabled = bool
      version = string
    })
    kong = object({ 
      enabled = bool
      version = string
    })
    traefik = object({ 
      enabled = bool
      version = string
    })
    tyk = object({ 
      enabled = bool
      version = string
    })
})

  default = {
    gravitee = {
      enabled = false
      version = ""
    }
    kong = { 
      enabled = false
      version = ""
    }
    traefik = { 
      enabled = true
      version = "v3.5.2"
    }
    tyk = { 
      enabled = false
      version = ""
    }
  }

  description = "A list of proivder objects that define the providers to be deployed."
}

variable "apim_providers_deployment" {
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

  default = {
    type          = "Deployment"
    replica_count = 1
    hpa = {
      enabled                 = false
      max_replica_count       = 1
      avg_cpu_util_percentage = 50
    }
    resources = {
      requests = {
        cpu    = "0"
        memory = "0"
      }
      limits = {
        cpu    = "0"
        memory = "0"
      }
    }
  }

  description = "Deployment description for providers."
}

variable "apim_providers_service" {
  type = object({
    type                    = string
    count                   = number
    external_traffic_policy = string
  })

  default = {
    type                    = "ClusterIP"
    count                   = 1
    external_traffic_policy = "Local"
  }

  description = "Service description for providers."
}

variable "apim_providers_route_count" {
  type        = number
  default     = 1
  description = "Route count for providers."
}

variable "apim_providers_middlewares" {
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

  default = {
    auth = {
      enabled   = false
      type      = ""
      app_count = 1
    }
    quota = {
      enabled = false
      rate    = 1
      per     = 1
    }
    rate_limit = {
      enabled = false
      rate    = 1
      per     = 1
    }
    observability = {
      logs = {
        enabled  = false
        exporter = ""
      }
      metrics = {
        enabled  = false
        exporter = ""
      }
      traces = {
        enabled  = false
        exporter = ""
        ratio    = ""
      }
    }
  }

  description = "Middleware description for providers."
}

variable "node_taints" {
  type = object({
    dependencies       = string
    upstream           = string
    upstream-loadgen   = string
    gravitee           = string
    gravitee-upstream  = string
    gravitee-loadgen   = string
    kong               = string
    kong-upstream      = string
    kong-loadgen       = string
    traefik            = string
    traefik-upstream   = string
    traefik-loadgen    = string
    tyk                = string
    tyk-upstream       = string
    tyk-loadgen        = string
  })

  default = {
    dependencies       = "dependencies"
    upstream           = "upstream"
    upstream-loadgen   = "upstream-loadgen"
    gravitee           = "gravitee"
    gravitee-upstream  = "gravitee-upstream"
    gravitee-loadgen   = "gravitee-loadgen"
    kong               = "kong"
    kong-upstream      = "kong-upstream"
    kong-loadgen       = "kong-loadgen"
    traefik            = "traefik"
    traefik-upstream   = "traefik-upstream"
    traefik-loadgen    = "traefik-loadgen"
    tyk                = "tyk"
    tyk-upstream       = "tyk-upstream"
    tyk-loadgen        = "tyk-loadgen"
  }
  description = "Mapping for node labels to determine the values for node selectors for each deployment."
}

variable "grafana_service_type" {
  type        = string
  default     = "ClusterIP"
  description = "Grafana Dashboard service type. Set to 'LoadBalancer' type to be able to access Dashboard over the internet."
}
