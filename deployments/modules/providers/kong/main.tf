terraform {
  required_providers {
    kubectl = {
      source  = "alekc/kubectl"
      version = ">= 2.0.4"
    }
  }
}

locals {
  redis_pass = "topsecretpassword"
  redis_port = "6379"

  tolerations = [{
    key      = "node"
    operator = "Equal"
    value    = var.taint
    effect   = "NoSchedule"
  }]
}

resource "kubernetes_namespace" "kong" {
  metadata {
    name = var.namespace
  }
}

module "upstream" {
  source        = "../../dependencies/upstream"
  namespace     = var.namespace
  taint         = var.upstream_taint
  service_count = var.service.count

  depends_on = [kubernetes_namespace.kong]
}

resource "helm_release" "kong" {
  name       = "kong"
  repository = "https://charts.konghq.com"
  chart      = "ingress"
  version    = "0.22.0"

  namespace = var.namespace
  atomic    = true
  wait      = true
  timeout   = 600

  values = [
    yamlencode({
      # --- Controller (KIC) ---------------------------------------------------
      controller = {
        ingressController = {
          enabled         = true
          watchNamespaces = [var.namespace]
          gatewayDiscovery = {
            enabled                 = true
            generateAdminApiService = true
          }
        }
        deployment = {
          kong = {
            enabled = false
          }
        }
        nodeSelector = {
          node = var.taint
        }
        tolerations = local.tolerations
        resources   = {}
      }

      # --- Gateway (data plane) ------------------------------------------------
      gateway = {
        enabled = true
        image = {
          tag = var.gateway_version
        }

        replicaCount = var.deployment.replica_count

        env = {
          role                            = "traditional"
          database                        = "off"
          nginx_worker_processes          = "auto"
          upstream_keepalive_max_requests = "999999"
          nginx_http_keepalive_requests   = "999999"
          proxy_access_log                = var.middlewares.observability.logs.enabled ? "/dev/stdout" : "off"
          tracing_instrumentations        = var.middlewares.observability.traces.enabled ? "all" : "off"
          tracing_sampling_rate           = var.middlewares.observability.traces.enabled ? "1" : "0"
        }

        admin = {
          enabled   = true
          type      = "ClusterIP"
          clusterIP = "None"
        }

        proxy = merge({
          type = var.service.type
          }, var.middlewares.tls.enabled ? {
          tls = {
            enabled       = true
            containerPort = 8443
            servicePort   = 443
          }
        } : {})

        ingressController = {
          enabled = false
        }

        service = {
          type = var.service.type
        }

        resources = var.deployment.resources.requests.cpu != "0" ? {
          requests = var.deployment.resources.requests
          limits   = var.deployment.resources.limits
        } : {}

        tolerations = local.tolerations

        nodeSelector = {
          node = var.taint
        }
      }
    })
  ]

  depends_on = [module.redis, module.upstream]
}
