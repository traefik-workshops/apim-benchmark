# ---------------------------------------------------------------------------
# Self-signed ClusterIssuer for benchmark TLS certificates
# Used by all APIM providers when tls.enabled = true
# ---------------------------------------------------------------------------
resource "kubectl_manifest" "selfsigned_cluster_issuer" {
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
