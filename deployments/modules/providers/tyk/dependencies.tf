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
    resources = {}
    master = {
      resources = {}
    }
  }

  depends_on = [kubernetes_namespace.tyk]
}
