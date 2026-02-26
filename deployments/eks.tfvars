kubernetes_config_path    = "~/.kube/config"
kubernetes_config_context = "benchmark"

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
    version = "v3.6.8"
  }
  kong = {
    enabled = true
    version = "3.9.1"
  }
  tyk = {
    enabled = true
    version = "v5.8.11"
  }
  gravitee = {
    enabled = true
    version = "4.10"
  }
  envoygateway = {
    enabled = true
    version = "v1.7.0"
  }
}

# --- Deployment settings (shared across providers) -------------------------
apim_providers_deployment = {
  type          = "Deployment"
  replica_count = 2
  hpa = {
    enabled                 = false
    max_replica_count       = 4
    avg_cpu_util_percentage = 60
  }
  resources = {
    requests = {
      cpu    = "500m"
      memory = "512Mi"
    }
    limits = {
      cpu    = "2000m"
      memory = "2Gi"
    }
  }
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
    rate    = 100
    per     = 3600
  }
  rate_limit = {
    enabled = false
    rate    = 100
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
      enabled  = true
      exporter = "prometheus"
    }
    traces = {
      enabled  = true
      exporter = "otlp"
      ratio    = "0.1"
    }
  }
}

# --- Domain & Dependencies -------------------------------------------------
domain                    = "benchmarks.demo.traefik.ai"
dependencies_service_type = "LoadBalancer"
grafana_service_type      = "LoadBalancer"

# --- Node taints (cloud: no per-workload isolation) -------------------------
# Cloud clusters use a flat node pool — all taints set to a common value.
# For per-workload isolation, configure node groups with labels manually.
node_taints = {
  dependencies          = "benchmark"
  upstream              = "benchmark"
  upstream-loadgen      = "benchmark"
  gravitee              = "benchmark"
  gravitee-upstream     = "benchmark"
  gravitee-loadgen      = "benchmark"
  kong                  = "benchmark"
  kong-upstream         = "benchmark"
  kong-loadgen          = "benchmark"
  traefik               = "benchmark"
  traefik-upstream      = "benchmark"
  traefik-loadgen       = "benchmark"
  tyk                   = "benchmark"
  tyk-upstream          = "benchmark"
  tyk-loadgen           = "benchmark"
  envoygateway          = "benchmark"
  envoygateway-upstream = "benchmark"
  envoygateway-loadgen  = "benchmark"
}
