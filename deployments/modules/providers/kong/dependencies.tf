module "redis" {
  source = "../../../../../terraform-demo-modules/tools/redis/k8s"

  name         = "kong-redis"
  namespace    = var.namespace
  password     = local.redis_pass
  replicaCount = 0

  extra_values = {
    master = {
      resources = {
        requests = null
        limits   = null
      }
    }
  }

  depends_on = [kubernetes_namespace_v1.kong]
}
