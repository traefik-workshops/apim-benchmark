module "pgsql" {
  source = "../../../../../terraform-demo-modules/tools/postgresql/k8s"

  name      = "gravitee-pgsql"
  namespace = var.namespace
  password  = local.pgsql_pass
  database  = local.pgsql_name

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
    # Postgres chart rejects null resources; empty object signals "unbounded".
    resources = {}
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

  depends_on = [kubernetes_namespace_v1.gravitee]
}

