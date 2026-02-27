resource "kubectl_manifest" "api" {
  yaml_body  = <<YAML
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: api-${count.index}
  namespace: "${var.namespace}"
  annotations:
    konghq.com/strip-path: 'true'
    konghq.com/plugins: "${local.plugins}"
    auth: "${var.middlewares.auth.type != "disabled" ? var.middlewares.auth.type : "Off"}"
    rate-limiting: "${var.middlewares.rate_limit.enabled ? format("%d/%d", var.middlewares.rate_limit.rate, var.middlewares.rate_limit.per) : "Off"}"
    quota: "${var.middlewares.quota.enabled ? format("%d/%d", var.middlewares.quota.rate, var.middlewares.quota.per) : "Off"}"
    open-telemetry-traces: "${var.middlewares.observability.traces.enabled ? "Always" : "Off"}"
    open-telemetry-metrics: "N/A"
    open-telemetry-logs: "N/A"
spec:
  ingressClassName: kong
%{if var.middlewares.tls.enabled~}
  tls:
  - secretName: gateway-tls-cert
%{endif~}
  rules:
  - http:
      paths:
      - path: /api-${count.index}
        pathType: ImplementationSpecific
        backend:
          service:
            name: fortio-${count.index % var.service.count}
            port:
              number: 8080
YAML
  count      = var.route_count
  depends_on = [helm_release.kong]
}
