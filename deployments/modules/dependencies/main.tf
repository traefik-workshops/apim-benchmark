terraform {
  required_providers {
    kubectl = {
      source  = "alekc/kubectl"
      version = ">= 2.0.4"
    }
  }
}

locals {
  tolerations = [{
    key      = "node"
    operator = "Equal"
    value    = var.taint
    effect   = "NoSchedule"
  }]
}

resource "kubernetes_namespace_v1" "dependencies" {
  metadata {
    name = var.namespace
  }
}

module "traefik" {
  source = "../../../../terraform-demo-modules/traefik/k8s"

  namespace             = var.namespace
  serviceType           = var.service_type
  traefik_chart_version = "39.0.8"
  skip_crds             = true
  kubernetes_namespaces = [var.namespace]
  ingress_class_name    = "traefik-dependencies"
  enable_access_logs    = false
  enable_dashboard      = true
  dashboard_insecure    = true
  tolerations           = local.tolerations

  dns_traefiker = {
    enabled     = var.dns_traefiker.enabled
    domain      = var.domain
    chart       = var.dns_traefiker.chart
    ip_override = var.dns_traefiker.ip_override
  }

  extra_values = {
    nodeSelector = {
      node = var.taint
    }
    service = {
      type = var.service_type
    }
    ports = {
      traefik = {
        expose = {
          default = false
        }
      }
    }
  }

  depends_on = [kubernetes_namespace_v1.dependencies]
}


module "cert-manager" {
  source = "../../../../terraform-demo-modules/tools/cert-manager/k8s"

  namespace = var.namespace

  depends_on = [kubernetes_namespace_v1.dependencies]
}

module "k6-operator" {
  source = "../../../../terraform-demo-modules/tools/k6-operator/k8s"

  namespace     = var.namespace
  node_selector = { node = var.taint }
  tolerations   = local.tolerations

  depends_on = [kubernetes_namespace_v1.dependencies]
}

module "keycloak" {
  source = "../../../../terraform-demo-modules/security/keycloak/k8s"

  name      = "keycloak"
  namespace = var.namespace
  chart     = var.keycloak.chart
  users     = [for i in range(10) : "user${i}@test.com"]

  domain = var.domain
  ingress = {
    enabled = true
  }

  count      = var.keycloak.enabled ? 1 : 0
  depends_on = [kubernetes_namespace_v1.dependencies]
}


# ---------------------------------------------------------------------------
# OpenTelemetry Collector
#
# Receives OTLP from the gateways (metrics, logs, traces) and forwards into
# the grafana-stack pipelines:
#   - traces  -> Tempo  (OTLP HTTP on 4318)
#   - logs    -> Loki   (OTLP HTTP on 3100/otlp)
#   - metrics -> Prometheus scrape target on :8889
#
# The chart names the Service "opentelemetry-collector" when the release
# name contains the chart name, so the gateway modules' hardcoded URL
# (http://opentelemetry-collector.dependencies.svc:4318) resolves without
# extra aliasing.
# ---------------------------------------------------------------------------
module "opentelemetry-collector" {
  source = "../../../../terraform-demo-modules/observability/opentelemetry/k8s"

  name      = "opentelemetry-collector"
  namespace = var.namespace

  enable_loki    = true
  loki_endpoint  = "http://loki.${var.namespace}.svc:3100/otlp"
  enable_tempo   = true
  tempo_endpoint = "http://tempo.${var.namespace}.svc:4318"

  enable_prometheus = true

  depends_on = [module.grafana-stack]
}

module "grafana-stack" {
  source = "../../../../terraform-demo-modules/observability/grafana-stack/k8s"

  namespace   = var.namespace
  tolerations = local.tolerations

  dashboards = {
    aigateway  = false
    mcpgateway = false
    apim       = false
  }

  extra_dashboards = {
    "k6-test-results" = file("${path.module}/dashboards/k6-test-results.json")
  }

  # Ingress via the dependencies-namespace Traefik instance
  ingress            = true
  ingress_domain     = var.domain
  ingress_entrypoint = "websecure"

  # Prometheus / kube-prometheus-stack overrides
  prometheus_extra_values = {
    prometheus = {
      prometheusSpec = {
        enableRemoteWriteReceiver = true
        tolerations               = local.tolerations
        nodeSelector              = { node = var.taint }
      }
    }
    kube-state-metrics = {
      tolerations           = local.tolerations
      nodeSelector          = { node = var.taint }
      metricLabelsAllowlist = ["nodes=[*]"]
    }
    prometheus-node-exporter = {
      tolerations = [{
        key      = "node"
        operator = "Exists"
        effect   = "NoSchedule"
      }]
    }
  }

  depends_on = [kubernetes_namespace_v1.dependencies]
}
