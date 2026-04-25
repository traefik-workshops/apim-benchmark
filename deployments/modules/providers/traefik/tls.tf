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

# ---------------------------------------------------------------------------
# TLSOption — pin Traefik's TLS handshake to TLS 1.3 only.
# Traefik applies a TLSOption named "default" in the route's namespace
# automatically to any route that doesn't reference an explicit option,
# so this resource alone is sufficient to lock the entrypoint without
# touching the IngressRoute. Min == max means no 1.2 fallback; under
# TLS 1.3 the cipher set collapses to the three RFC 8446 AEADs that
# Traefik (Go crypto/tls) hardcodes.
# ---------------------------------------------------------------------------
resource "kubectl_manifest" "tls_option_default" {
  yaml_body = <<YAML
apiVersion: traefik.io/v1alpha1
kind: TLSOption
metadata:
  name: default
  namespace: ${var.namespace}
spec:
  minVersion: VersionTLS13
  maxVersion: VersionTLS13
YAML

  count      = var.middlewares.tls.enabled ? 1 : 0
  depends_on = [helm_release.traefik]
}
