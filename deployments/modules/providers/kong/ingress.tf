resource "kubectl_manifest" "api" {
  yaml_body  = <<YAML
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: api-${count.index}
  namespace: "${var.namespace}"
  annotations:
    konghq.com/strip-path: 'false'
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
    # Kong maps a cert to SNI hostnames via the Ingress TLS block's
    # `hosts` field. Without an entry here Kong falls back to its
    # bundled CN=localhost cert for every SNI. The cert's SANs are
    # *.<namespace>.svc and *.<namespace>.svc.cluster.local, so list
    # both to cover in-cluster service DNS in either form.
    hosts:
    - "*.${var.namespace}.svc"
    - "*.${var.namespace}.svc.cluster.local"
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
