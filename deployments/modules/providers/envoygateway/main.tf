terraform {
  required_providers {
    kubectl = {
      source  = "alekc/kubectl"
      version = ">= 2.0.4"
    }
  }
}

resource "kubernetes_namespace_v1" "envoygateway" {
  metadata {
    name = var.namespace
  }
}

module "upstream" {
  source        = "../../dependencies/upstream"
  namespace     = var.namespace
  taint         = var.upstream_taint
  service_count = var.service.count

  depends_on = [kubernetes_namespace_v1.envoygateway]
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
  name       = "envoy-gateway"
  repository = "oci://docker.io/envoyproxy"
  chart      = "gateway-helm"
  version    = var.gateway_version

  namespace        = var.namespace
  atomic           = true
  wait             = true
  timeout          = 300
  create_namespace = false

  # NOTE: the two-entry values list is intentional. Helm deep-merges maps,
  # so passing `resources: {}` (which is all yamlencode can produce for an
  # "empty" map — it drops null attrs) is a no-op against the chart's default
  # {limits: 1024Mi, requests: 100m/256Mi}. To actually strip the defaults we
  # have to emit `limits: null` / `requests: null` as raw YAML; yamlencode
  # can't express that. The second values entry is a heredoc that does.
  values = concat(
    [yamlencode({
      deployment = {
        envoyGateway = var.deployment.resources != null ? {
          resources = {
            requests = var.deployment.resources.requests
            limits   = var.deployment.resources.limits
          }
        } : {}
        pod = {
          nodeSelector = {
            node = var.taint
          }
          tolerations = local.tolerations
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
    })],
    var.deployment.resources == null ? [<<-YAML
      deployment:
        envoyGateway:
          resources:
            limits: null
            requests: null
    YAML
    ] : []
  )

  depends_on = [kubernetes_namespace_v1.envoygateway]
}

# ---------------------------------------------------------------------------
# Stable service for the Envoy proxy data plane
# The Envoy Gateway controller creates proxy pods with the label
# gateway.envoyproxy.io/owning-gateway-name=envoy-gateway.
# We create a fixed-name ClusterIP service so k6 tests can target it.
# ---------------------------------------------------------------------------
resource "kubernetes_service_v1" "envoy_proxy" {
  metadata {
    name      = "envoy-gateway-proxy"
    namespace = var.namespace
  }

  spec {
    type = "ClusterIP"

    selector = {
      "gateway.envoyproxy.io/owning-gateway-name"      = "envoy-gateway"
      "gateway.envoyproxy.io/owning-gateway-namespace" = var.namespace
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
