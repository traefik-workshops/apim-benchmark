# ---------------------------------------------------------------------------
# Rate Limiting — BackendTrafficPolicy (one per HTTPRoute)
# ---------------------------------------------------------------------------
resource "kubectl_manifest" "rate_limit" {
  yaml_body = <<YAML
apiVersion: gateway.envoyproxy.io/v1alpha1
kind: BackendTrafficPolicy
metadata:
  name: rate-limit-${count.index}
  namespace: ${var.namespace}
spec:
  targetRefs:
  - group: gateway.networking.k8s.io
    kind: HTTPRoute
    name: api-${count.index}
  rateLimit:
    type: Local
    local:
      rules:
      - limit:
          requests: ${var.middlewares.rate_limit.rate}
          unit: Second
YAML

  count      = var.middlewares.rate_limit.enabled ? var.route_count : 0
  depends_on = [kubectl_manifest.api]
}

# ---------------------------------------------------------------------------
# Auth — SecurityPolicy with JWT Keycloak (RSA via remoteJWKS)
# ---------------------------------------------------------------------------
resource "kubectl_manifest" "auth-jwt-keycloak" {
  yaml_body = <<YAML
apiVersion: gateway.envoyproxy.io/v1alpha1
kind: SecurityPolicy
metadata:
  name: auth-${count.index}
  namespace: ${var.namespace}
spec:
  targetRefs:
  - group: gateway.networking.k8s.io
    kind: HTTPRoute
    name: api-${count.index}
  jwt:
    providers:
    - name: keycloak
      issuer: http://keycloak-service.dependencies.svc:8080/realms/traefik
      remoteJWKS:
        uri: http://keycloak-service.dependencies.svc:8080/realms/traefik/protocol/openid-connect/certs
YAML

  count      = var.middlewares.auth.type == "jwt_keycloak" ? var.route_count : 0
  depends_on = [kubectl_manifest.api]
}
