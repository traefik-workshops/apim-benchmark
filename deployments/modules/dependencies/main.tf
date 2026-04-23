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
  traefik_chart_version = var.traefik_chart_version
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
  instances = var.keycloak.instances
  users     = [for i in range(10) : "user${i}@test.com"]

  domain = var.domain
  ingress = {
    enabled = true
  }

  count = var.keycloak.enabled ? 1 : 0
  # The dep-Traefik Helm chart installs the Traefik + Gateway API + Hub CRDs
  # as part of its templates/. Keycloak's chart references Middleware, so
  # its install has to start after dep-Traefik's is Created.
  depends_on = [kubernetes_namespace_v1.dependencies, module.traefik]
}


# ---------------------------------------------------------------------------
# VictoriaMetrics Cluster
#
# Replaces kube-prometheus-stack Prometheus as the authoritative remote-
# write receiver + query backend. VM scales horizontally (vminsert shards
# writes across vmstorage nodes, vmselect fans out queries), so aggregate
# ingest throughput grows with replica count instead of being pinned to
# whatever a single Prometheus pod can absorb.
#
# All three tiers are scaled by enabled provider count — one replica per
# provider, minimum 2 — which matches the parallel test-run shape.
#
# Services exposed (fullnameOverride = "vm" so names stay short):
#   - vm-vminsert  :8480   receive remote-write (k6 runners + kube-prom)
#   - vm-vmselect  :8481   Prom-compatible query API (Grafana datasource)
#   - vm-vmstorage :8482/8400/8401  internal
# ---------------------------------------------------------------------------
resource "helm_release" "victoria_metrics" {
  name       = "vm"
  repository = "https://victoriametrics.github.io/helm-charts/"
  chart      = "victoria-metrics-cluster"
  version    = "0.39.0"
  namespace  = var.namespace
  timeout    = 600
  atomic     = true

  values = [
    yamlencode({
      fullnameOverride = "vm"

      vminsert = {
        replicaCount = var.vm_replicas
        extraArgs = {
          # Accept Prom remote-write on the default Prom path so existing
          # k6 runners and kube-prometheus-stack point here unchanged.
          "httpListenAddr" = ":8480"
          # GKE's kube_node_labels exposes 42 labels per node (addon_*,
          # cloud_google_com_*, disk_type_gke_io_*, topology_*, our own
          # label_node, etc.). Default limit is 30 → series silently dropped.
          # Bump to 64 to cover GKE's sprawl with headroom.
          "maxLabelsPerTimeseries" = "64"
        }
        tolerations  = local.tolerations
        nodeSelector = { node = var.taint }
      }

      vmselect = {
        replicaCount = var.vm_replicas
        tolerations  = local.tolerations
        nodeSelector = { node = var.taint }
      }

      vmstorage = {
        replicaCount = var.vm_replicas
        tolerations  = local.tolerations
        nodeSelector = { node = var.taint }
        persistentVolume = {
          enabled = false
        }
      }
    })
  ]

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

  # Prometheus / kube-prometheus-stack overrides.
  #
  # VictoriaMetrics is the authoritative query backend, but kube-prometheus-
  # stack still runs so its ServiceMonitor scraping (node_exporter,
  # kube-state-metrics, etc.) keeps working. Prometheus now remote-writes
  # every scrape sample into VM-vminsert, so Grafana can query both
  # scrape data and k6 remote-write data from the same backend.
  prometheus_extra_values = {
    prometheus = {
      prometheusSpec = {
        # Prom itself no longer receives remote-write from k6 (k6 points at
        # vminsert directly); drop the receiver flag.
        enableRemoteWriteReceiver = false
        tolerations               = local.tolerations
        nodeSelector              = { node = var.taint }
        remoteWrite = [{
          url = "http://vm-vminsert.${var.namespace}.svc:8480/insert/0/prometheus/api/v1/write"
        }]
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

  # Point Grafana's Prometheus datasource at VictoriaMetrics vmselect (Prom-
  # compatible query API) so the shipped k6-test-results dashboard (which
  # hardcodes datasource UID PBFA97CFB590B2093) queries VM without any
  # dashboard rewrites.
  prometheus_url_override = "http://vm-vmselect.${var.namespace}.svc:8481/select/0/prometheus"

  depends_on = [kubernetes_namespace_v1.dependencies, helm_release.victoria_metrics]
}
