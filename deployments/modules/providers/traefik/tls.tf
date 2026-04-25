# ---------------------------------------------------------------------------
# TLS Certificate (cert-manager) for Traefik
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
  # Pin keypair so every provider serves a cert with identical algorithm
  # parameters. RSA-2048 + SHA-256 signature is the production-default
  # combo (Mozilla "modern" profile, ~99% of public TLS handshakes today)
  # and is universally supported by every gateway's TLS stack.
  privateKey:
    algorithm: RSA
    size: 2048
  dnsNames:
  - "*.${var.namespace}.svc"
  - "*.${var.namespace}.svc.cluster.local"
  duration: 8760h
  renewBefore: 720h
YAML

  count      = var.middlewares.tls.enabled ? 1 : 0
  depends_on = [kubernetes_namespace_v1.traefik]
}
