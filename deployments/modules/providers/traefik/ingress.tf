locals {
  # Rate limiting is handled by Hub APIRateLimit CRD (not IngressRoute middleware)
  middleware_refs = compact([
    local.has_headers ? "- name: headers" : "",
  ])
  middlewares_block = length(local.middleware_refs) > 0 ? "middlewares:\n    ${join("\n    ", local.middleware_refs)}" : ""
  tls_block         = var.middlewares.tls.enabled ? "\n  tls:\n    secretName: gateway-tls-cert" : ""
}

resource "kubectl_manifest" "api" {
  yaml_body  = <<YAML
apiVersion: traefik.io/v1alpha1
kind: IngressRoute
metadata:
  name: api-${count.index}
  namespace: ${var.namespace}
  annotations:
    hub.traefik.io/api: benchmark-api-${count.index}
    hub.traefik.io/api-version: benchmark-api-${count.index}-v1
    auth: "${var.middlewares.auth.type != "disabled" ? var.middlewares.auth.type : "Off"}"
    rate-limiting: "${var.middlewares.rate_limit.enabled ? format("%d/%d", var.middlewares.rate_limit.rate, var.middlewares.rate_limit.per) : "Off"}"
    quota: "${var.middlewares.quota.enabled ? format("%d/%d", var.middlewares.quota.rate, var.middlewares.quota.per) : "Off"}"
    open-telemetry-traces: "${var.middlewares.observability.traces.enabled ? "Always" : "Off"}"
    open-telemetry-metrics: "${var.middlewares.observability.metrics.enabled ? "On" : "Off"}"
    open-telemetry-logs: "${var.middlewares.observability.logs.enabled ? "On" : "Off"}"
spec:
  entryPoints:
  - ${var.middlewares.tls.enabled ? "websecure" : "web"}
  routes:
  - kind: Rule
    match: PathPrefix(`/api-${count.index}`)
    ${local.middlewares_block}
    services:
    - name: fortio-${count.index % var.service.count}
      port: 8080${local.tls_block}
YAML
  count      = var.route_count
  depends_on = [helm_release.traefik]
}
