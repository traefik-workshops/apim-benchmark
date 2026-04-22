locals {
  redis_pass = "topsecretpassword"
  redis_port = 6379
  redis_name = "tyk-redis"
}

# ---------------------------------------------------------------------------
# Redis (using terraform-demo-modules)
# ---------------------------------------------------------------------------
module "redis" {
  source = "../../../../../terraform-demo-modules/tools/redis/k8s"

  name         = local.redis_name
  namespace    = var.namespace
  password     = local.redis_pass
  replicaCount = 0

  extra_values = {
    nodeSelector = { node = var.taint }
    tolerations = [{
      key      = "node"
      operator = "Equal"
      value    = var.taint
      effect   = "NoSchedule"
    }]
    # Ephemeral storage — benchmark is short-lived and does not test durability;
    # emptyDir avoids local-path PV node-affinity conflicts when reassigning
    # the backing store between provider nodes.
    persistence = { enabled = false }
    resources = {
      requests = null
      limits   = null
    }
  }

  depends_on = [kubernetes_namespace_v1.tyk]
}
