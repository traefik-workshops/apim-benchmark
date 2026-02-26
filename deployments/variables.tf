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
    envoygateway = object({
      enabled = bool
      version = string
    })
  })

  default = {
    gravitee = {
      enabled = false
      version = "4.10"
    }
    kong = {
      enabled = false
      version = "3.9"
    }
    traefik = {
      enabled = true
      version = "v3.6.8"
    }
    tyk = {
      enabled = false
      version = "v5.8"
    }
    envoygateway = {
      enabled = false
      version = "v1.3.0"
    }
  }

  description = "A list of provider objects that define the providers to be deployed."
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
      type      = string # "disabled" | "token_postgres" | "token_iac" | "jwt_hmac" | "jwt_keycloak"
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
      logs = object({
        enabled  = bool
        exporter = string # "otlp" | "stdout"
      })
      metrics = object({
        enabled  = bool
        exporter = string # "otlp" | "prometheus"
      })
      traces = object({
        enabled  = bool
        exporter = string # "otlp"
        ratio    = string
      })
    })
  })

  default = {
    auth = {
      type      = "disabled"
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
    tls = {
      enabled = false
    }
    headers = {
      request = {
        set    = {}
        remove = []
      }
      response = {
        set    = {}
        remove = []
      }
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

  description = "Middleware configuration for all APIM providers."
}

variable "node_taints" {
  type = object({
    dependencies          = string
    upstream              = string
    upstream-loadgen      = string
    gravitee              = string
    gravitee-upstream     = string
    gravitee-loadgen      = string
    kong                  = string
    kong-upstream         = string
    kong-loadgen          = string
    traefik               = string
    traefik-upstream      = string
    traefik-loadgen       = string
    tyk                   = string
    tyk-upstream          = string
    tyk-loadgen           = string
    envoygateway          = string
    envoygateway-upstream = string
    envoygateway-loadgen  = string
  })

  default = {
    dependencies          = "dependencies"
    upstream              = "upstream"
    upstream-loadgen      = "upstream-loadgen"
    gravitee              = "gravitee"
    gravitee-upstream     = "gravitee-upstream"
    gravitee-loadgen      = "gravitee-loadgen"
    kong                  = "kong"
    kong-upstream         = "kong-upstream"
    kong-loadgen          = "kong-loadgen"
    traefik               = "traefik"
    traefik-upstream      = "traefik-upstream"
    traefik-loadgen       = "traefik-loadgen"
    tyk                   = "tyk"
    tyk-upstream          = "tyk-upstream"
    tyk-loadgen           = "tyk-loadgen"
    envoygateway          = "envoygateway"
    envoygateway-upstream = "envoygateway-upstream"
    envoygateway-loadgen  = "envoygateway-loadgen"
  }
  description = "Mapping for node labels to determine the values for node selectors for each deployment."
}

# ---------------------------------------------------------------------------
# Domain & Dependencies
# ---------------------------------------------------------------------------

variable "domain" {
  type        = string
  default     = "benchmarks.demo.traefik.ai"
  description = "Base domain for DNS and ingress."
}

variable "dependencies_service_type" {
  type        = string
  default     = "LoadBalancer"
  description = "Service type for the dependencies Traefik instance."
}

variable "dns_traefiker" {
  type = object({
    enabled = bool
    chart   = string
  })
  default = {
    enabled = false
    chart   = ""
  }
  description = "DNS Traefiker configuration for automatic Cloudflare DNS registration."
}

variable "grafana_service_type" {
  type        = string
  default     = "ClusterIP"
  description = "Service type for the Grafana instance."
}

variable "traefik_hub_token" {
  type        = string
  default     = ""
  sensitive   = true
  description = "Traefik Hub license token for API Gateway features."
}
