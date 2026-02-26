kubernetes_config_path    = "~/.kube/config"
kubernetes_config_context = "k3d-benchmark"

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
# All 5 APIM providers enabled for benchmarking.
# Override with -var on the CLI or edit this file to disable providers.
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
  replica_count = 1
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

apim_providers_service = {
  type                    = "ClusterIP"
  count                   = 1
  external_traffic_policy = "Local"
}

apim_providers_route_count = 1

# --- Middlewares ---------------------------------------------------------------
# auth.type: "disabled" | "token_postgres" | "token_iac" | "jwt_hmac" | "jwt_keycloak"
# observability: all signals exported via OTLP to opentelemetry-collector.dependencies.svc
apim_providers_middlewares = {
  auth = {
    type      = "jwt_keycloak"
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
    enabled = true
  }
  headers = {
    request = {
      set    = { "X-Benchmark-Req" = "hello" }
      remove = ["X-Remove-Me"]
    }
    response = {
      set    = { "X-Benchmark-Resp" = "world" }
      remove = ["X-Remove-Resp"]
    }
  }
  observability = {
    metrics = { enabled = true }
    logs    = { enabled = false }
    traces = {
      enabled = true
      ratio   = "0.1"
    }
  }
}

# --- Domain & Dependencies -------------------------------------------------
domain                    = "benchmarks.demo.traefik.ai"
dependencies_service_type = "LoadBalancer"
grafana_service_type      = "ClusterIP"

dns_traefiker = {
  enabled = true
  chart   = "/Users/zaidalbirawi/dev/traefik-demo-resources/dns-traefiker/helm"
}

traefik_hub_token = "eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJodHRwczovL2h1Yi50cmFlZmlrLmlvIiwic3ViIjoiNjg2NTQ2Yzc2ZjgwMmJjODZkYWJiZGI2LTdmY2M4MTU2LTUxMjEtNGI3OS05NTA0LTZlNjU4MWEyYjA5MyIsImF1ZCI6WyJ0cmFlZmlrLWh1Yi1nYXRld2F5Il0sIm5iZiI6MTc3MTkwNTYzOSwiaWF0IjoxNzcxOTA1NjM5LCJqdGkiOiI5NzY2NTNkYS0xODc2LTQxY2ItOTA5Yi1iMzk0NGYzMzk0MGEiLCJ0b2tlbiI6Ijk0YmNjNDdhLWYzNWYtNDFiMC04MTAyLWIxMThhZDA2NTZmZiIsImNsdXN0ZXJJZCI6IjdmY2M4MTU2LTUxMjEtNGI3OS05NTA0LTZlNjU4MWEyYjA5MyIsIndvcmtzcGFjZUlkIjoiNjg2NTQ2Yzc2ZjgwMmJjODZkYWJiZGI2Iiwib2ZmbGluZSI6dHJ1ZSwiZXhwaXJhdGlvbkRhdGUiOiIyMDI2LTA3LTI5VDA0OjAwOjAwWiIsInBsYXRmb3JtVXJsIjoiaHR0cHM6Ly9hcGkudHJhZWZpay5pby9hZ2VudCJ9.p7pegVDUcv1r7blq-H3b4zNzVilFI_1tgyBlQQQlPZck6t4-Yw9tNGU5HL-xic25_157zs74XGBwdMmUQBpWofFNrKmWuEdxSu51kccLc0gQcOPCFm9Z6vsFCi7xjhe3poZkuDRZwSVIdLS0IIWh8KceHUpg4TXCLB05dj50Yx2DCPt0RNOLDuPYPYo8kdc7gb5YuLEw-jqlsCSchpeKwgy9zEFlvcD0_8ZCfRARLCNfvWm2yBJtT_vcR7o_Rh8z_QfpikKeOpF10CGWFoEV1Vz5zsFbHliumtcvojejVFqGqzOkXpw7DrI_JjvlfSJVIDPjqx6kd8W0NmOytLBZl0CixvNBkSjITr8GcrtmwwRncijPGN3aiNuk-cPi2voeUVDyLh6sEdhMM5RBEc7f4X6k6skQktQ-MCEj0Ecekm___ncNnYg03GOepC-MWl1elLzgZ2bHIlsNg92kq7gpKE1z8CZPalCo5he4k5lkUAmbAti58q1IzWJc3yNipgNJgIE_4hJdbg5Hm9cLBm_TwJ_7ihOjF0z2oIkDrxvC9rYHaXj6rMvfFj9YZukLuKX4zCXCKv7zymc772s_Hmrm1kz0LmP1bnXbUir1LR0bohJFKWpHHuLXusHgE5meiVDghXmIOayvsvs6sTG5bT7K1eNbOKlgZkAMfrsmES44eHs"
