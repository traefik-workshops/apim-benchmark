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

resource "kubernetes_namespace" "dependencies" {
  metadata {
    name = var.namespace
  }
}

module "traefik" {
  source = "../../../../terraform-demo-modules/traefik/k8s"

  namespace                = var.namespace
  serviceType              = var.service_type
  traefik_chart_version    = "39.0.2"
  skip_crds                = true
  kubernetes_namespaces    = [var.namespace]
  ingress_class_name       = "traefik-dependencies"
  ingress_class_is_default = false
  enable_access_logs       = false
  enable_dashboard         = true
  dashboard_insecure       = true
  tolerations              = local.tolerations

  dns_traefiker = {
    enabled = false
    domain  = var.domain
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

  depends_on = [kubernetes_namespace.dependencies]
}


module "cert-manager" {
  source = "../../../../terraform-demo-modules/tools/cert-manager/k8s"

  namespace = var.namespace

  depends_on = [kubernetes_namespace.dependencies]
}

module "k6-operator" {
  source = "../../../../terraform-demo-modules/tools/k6-operator/k8s"

  namespace     = var.namespace
  node_selector = { node = var.taint }
  tolerations   = local.tolerations

  depends_on = [kubernetes_namespace.dependencies]
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
  depends_on = [kubernetes_namespace.dependencies]
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
      tolerations = local.tolerations
    }
  }

  depends_on = [kubernetes_namespace.dependencies]
}
