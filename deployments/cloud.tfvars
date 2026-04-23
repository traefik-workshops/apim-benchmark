kubernetes_config_path    = "~/.kube/config"
kubernetes_config_context = "gke-benchmark"

# --- Upstream (baseline) ---------------------------------------------------
upstream = {
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

# --- Providers --------------------------------------------------------------
apim_providers = {
  traefik = {
    enabled = true
    version = "v3.6.13"
  }
  kong = {
    enabled = true
    version = "3.9.1"
  }
  tyk = {
    enabled = true
    version = "v5.11.0"
  }
  gravitee = {
    enabled = true
    version = "4.11.4"
  }
  envoygateway = {
    enabled = true
    version = "v1.7.2"
  }
}

# --- Deployment settings (shared across providers) -------------------------
apim_providers_deployment = {
  type          = "Deployment"
  replica_count = 1
}

apim_providers_service = {
  type                    = "ClusterIP"
  count                   = 1
  external_traffic_policy = "Local"
}

apim_providers_route_count = 1

# --- Middlewares ---------------------------------------------------------------
apim_providers_middlewares = {
  auth = {
    type      = "disabled"
    app_count = 1
  }
  quota = {
    enabled = false
    rate    = 999999
    per     = 3600
  }
  rate_limit = {
    enabled = false
    rate    = 999999
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

# --- Domain & Dependencies -------------------------------------------------
domain                    = "benchmarks.demo.traefik.ai"
dependencies_service_type = "LoadBalancer"

dns_traefiker = {
  enabled = true
}

# Traefik Hub token is read from environment (TF_VAR_traefik_hub_token) or
# from a machine-local `deployments/secrets.auto.tfvars` (gitignored). Leave
# unset to deploy Traefik as OSS without Hub features.
