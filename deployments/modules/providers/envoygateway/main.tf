terraform {
  required_providers {
    kubectl = {
      source  = "alekc/kubectl"
      version = ">= 2.0.4"
    }
  }
}

resource "kubernetes_namespace" "envoygateway" {
  metadata {
    name = var.namespace
  }
}

module "upstream" {
  source        = "../../dependencies/upstream"
  namespace     = var.namespace
  taint         = var.upstream_taint
  service_count = var.service.count

  depends_on = [kubernetes_namespace.envoygateway]
}

locals {
  tolerations = [{
    key      = "node"
    operator = "Equal"
    value    = var.taint
    effect   = "NoSchedule"
  }]
}

# ---------------------------------------------------------------------------
# Envoy Gateway (installs Gateway API CRDs automatically)
# ---------------------------------------------------------------------------
resource "helm_release" "envoygateway" {
  name             = "envoy-gateway"
  repository       = "oci://docker.io/envoyproxy"
  chart            = "gateway-helm"
  version          = var.gateway_version

  namespace        = var.namespace
  atomic           = true
  wait             = true
  timeout          = 300
  create_namespace = false

  values = [
    yamlencode({
      deployment = {
        envoyGateway = {
          resources = var.deployment.resources.requests.cpu != "0" ? {
            requests = var.deployment.resources.requests
            limits   = var.deployment.resources.limits
          } : null
        }
      }

      config = {
        envoyGateway = {
          gateway = {
            controllerName = "gateway.envoyproxy.io/gatewayclass-controller"
          }
          provider = {
            type = "Kubernetes"
          }
          logging = {
            level = {
              default = "info"
            }
          }
        }
      }
    })
  ]

  depends_on = [kubernetes_namespace.envoygateway]
}

# ---------------------------------------------------------------------------
# Stable service for the Envoy proxy data plane
# The Envoy Gateway controller creates proxy pods with the label
# gateway.envoyproxy.io/owning-gateway-name=envoy-gateway.
# We create a fixed-name ClusterIP service so k6 tests can target it.
# ---------------------------------------------------------------------------
resource "kubernetes_service" "envoy_proxy" {
  metadata {
    name      = "envoy-gateway-proxy"
    namespace = var.namespace
  }

  spec {
    type = "ClusterIP"

    selector = {
      "gateway.envoyproxy.io/owning-gateway-name"      = "envoy-gateway"
      "gateway.envoyproxy.io/owning-gateway-namespace"  = var.namespace
    }

    port {
      name        = "http"
      port        = 8080
      target_port = 8080
      protocol    = "TCP"
    }

    dynamic "port" {
      for_each = var.middlewares.tls.enabled ? [1] : []
      content {
        name        = "https"
        port        = 8443
        target_port = 8443
        protocol    = "TCP"
      }
    }
  }

  depends_on = [kubectl_manifest.gateway]
}
