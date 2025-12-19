resource "kubectl_manifest" "api" {
  yaml_body = <<YAML
apiVersion: traefik.io/v1alpha1
kind: IngressRoute
metadata:
  name: api-${count.index}
  namespace: ${var.namespace}
  annotations:
    auth: "${var.middlewares.auth.enabled ? var.middlewares.auth.type : "Off"}"
    rate-limiting: "${var.middlewares.rate_limit.enabled ? format("%d/%d", var.middlewares.rate_limit.rate, var.middlewares.rate_limit.per) : "Off"}"
    quota: "${var.middlewares.quota.enabled ? format("%d/%d", var.middlewares.quota.rate, var.middlewares.quota.per) : "Off"}"
    open-telemetry-traces: "${var.middlewares.observability.traces.enabled ? var.middlewares.observability.traces.ratio : "Off"}"
    open-telemetry-metrics: "${var.middlewares.observability.metrics.enabled ? "On" : "Off"}"
    open-telemetry-logs: "${var.middlewares.observability.logs.enabled ? "On" : "Off"}"
spec:
  entryPoints:
  - web
  routes:
  - kind: Rule
    match: PathPrefix(`/api-${count.index}`)
    services:
    - name: fortio-${count.index % var.service.count}
      port: 8080
YAML
  count      = var.route_count
  depends_on = [module.traefik]
}
