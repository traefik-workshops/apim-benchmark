module "pgsql" {
  source = "../../../../../terraform-demo-modules/tools/postgresql/k8s"

  name      = "gravitee-pgsql"
  namespace = var.namespace
  password  = local.pgsql_pass
  database  = local.pgsql_name

  extra_values = {
    primary = {
      resources = {
        requests = null
        limits   = null
      }
    }
  }

  depends_on = [kubernetes_namespace_v1.gravitee]
}

module "redis" {
  source = "../../../../../terraform-demo-modules/tools/redis/k8s"

  name         = "gravitee-redis"
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

  depends_on = [kubernetes_namespace_v1.gravitee]
}

