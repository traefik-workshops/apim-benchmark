# ---------------------------------------------------------------------------
# TLS Certificate (cert-manager) for Kong proxy
# ---------------------------------------------------------------------------
resource "kubectl_manifest" "tls_certificate" {
  yaml_body = <<YAML
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: gateway-tls
  namespace: ${var.namespace}
spec:
  secretName: gateway-tls-cert
  issuerRef:
    name: selfsigned-issuer
    kind: ClusterIssuer
  dnsNames:
  - "*.${var.namespace}.svc"
  - "*.${var.namespace}.svc.cluster.local"
  duration: 8760h
  renewBefore: 720h
YAML

  count      = var.middlewares.tls.enabled ? 1 : 0
  depends_on = [kubernetes_namespace.kong]
}
