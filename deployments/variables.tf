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
    # null (the default) means "no resources configured" — providers skip
    # emitting the resources block, or emit explicit-null overrides when
    # the Helm chart's own defaults would otherwise apply (envoygateway).
    # Set this to populate requests/limits on the gateway pod.
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

  default = {
    type          = "Deployment"
    replica_count = 1
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
      metrics = object({ enabled = bool })
      logs    = object({ enabled = bool })
      traces  = object({ enabled = bool })
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
      metrics = { enabled = false }
      logs    = { enabled = false }
      traces  = { enabled = false }
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
    enabled     = bool
    ip_override = optional(string, "")
  })
  default = {
    enabled     = false
    ip_override = ""
  }
  description = "DNS Traefiker configuration for automatic Cloudflare DNS registration. Chart path is controlled by var.dns_traefiker_chart."
}


variable "traefik_hub_token" {
  type        = string
  default     = ""
  sensitive   = true
  description = "Traefik Hub license token for API Gateway features."
}

# ---------------------------------------------------------------------------
# Local Helm chart paths
#
# The Keycloak and DNS Traefiker charts live in the sibling
# `traefik-demo-resources/` checkout. The default paths assume the expected
# `<parent>/{apim-benchmark,traefik-demo-resources}/` layout, but anyone can
# override via `TF_VAR_<name>` or a machine-local secrets.auto.tfvars to
# point at a chart in a different location.
# ---------------------------------------------------------------------------

variable "keycloak_chart" {
  type        = string
  default     = ""
  description = "Filesystem path to the Keycloak Helm chart. Empty → use ../../traefik-demo-resources/keycloak/helm relative to the deployments/ module."
}

variable "dns_traefiker_chart" {
  type        = string
  default     = ""
  description = "Filesystem path to the DNS Traefiker Helm chart. Empty → use ../../traefik-demo-resources/dns-traefiker/helm relative to the deployments/ module."
}
