# ---------------------------------------------------------------------------
# Self-signed ClusterIssuer for TLS certificates
# Used by per-provider tls.tf modules (gateway-tls-cert secrets).
# ---------------------------------------------------------------------------
resource "kubectl_manifest" "selfsigned_issuer" {
  yaml_body = <<YAML
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: selfsigned-issuer
spec:
  selfSigned: {}
YAML

  depends_on = [module.cert-manager]
}
