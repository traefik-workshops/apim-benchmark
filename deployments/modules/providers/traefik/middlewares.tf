locals {
  has_req_headers  = length(var.middlewares.headers.request.set) > 0 || length(var.middlewares.headers.request.remove) > 0
  has_resp_headers = length(var.middlewares.headers.response.set) > 0 || length(var.middlewares.headers.response.remove) > 0
  has_headers      = local.has_req_headers || local.has_resp_headers

  # Combine set and remove headers (in Traefik, setting a header to "" removes it)
  request_headers = merge(
    var.middlewares.headers.request.set,
    { for name in var.middlewares.headers.request.remove : name => "" }
  )
  response_headers = merge(
    var.middlewares.headers.response.set,
    { for name in var.middlewares.headers.response.remove : name => "" }
  )

  # Hub API management is needed when any of auth, rate-limit, or quota are active
  needs_hub_api = var.middlewares.auth.type != "disabled" || var.middlewares.rate_limit.enabled || var.middlewares.quota.enabled
}

# ---------------------------------------------------------------------------
# Header Manipulation — Traefik Middleware CRD (OSS — no Hub equivalent)
# ---------------------------------------------------------------------------
resource "kubectl_manifest" "headers_middleware" {
  yaml_body = <<YAML
apiVersion: traefik.io/v1alpha1
kind: Middleware
metadata:
  name: headers
  namespace: ${var.namespace}
spec:
  headers:
%{if length(local.request_headers) > 0~}
    customRequestHeaders:
%{for name, value in local.request_headers~}
      ${name}: "${value}"
%{endfor~}
%{endif~}
%{if length(local.response_headers) > 0~}
    customResponseHeaders:
%{for name, value in local.response_headers~}
      ${name}: "${value}"
%{endfor~}
%{endif~}
YAML

  count      = local.has_headers ? 1 : 0
  depends_on = [helm_release.traefik]
}

# ---------------------------------------------------------------------------
# Auth — Traefik Hub APIAuth (JWT via Keycloak JWKS)
# Hub APIAuth requires HTTPS for jwksUrl.
# ---------------------------------------------------------------------------
resource "kubectl_manifest" "api_auth" {
  yaml_body = <<YAML
apiVersion: hub.traefik.io/v1alpha1
kind: APIAuth
metadata:
  name: jwt-auth-keycloak
  namespace: ${var.namespace}
spec:
  isDefault: true
  jwt:
    jwksUrl: https://keycloak-service.dependencies.svc:8443/realms/traefik/protocol/openid-connect/certs
    stripAuthorizationHeader: false
    appIdClaim: sub
YAML

  # Requires Keycloak TLS — enabled only when jwt_keycloak + TLS are both active
  count      = var.middlewares.auth.type == "jwt_keycloak" && var.middlewares.tls.enabled ? 1 : 0
  depends_on = [helm_release.traefik]
}

# ---------------------------------------------------------------------------
# Auth — JWT HMAC (HS256)
# NOTE: Hub APIAuth requires a JWKS URL. HMAC (HS256) uses symmetric secrets
# which cannot be served via standard JWKS. Requires ForwardAuth or plugin.
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# Auth — token_iac (API keys via Hub ManagedSubscription)
# Creates ManagedApplication + Secrets + ManagedSubscription linking to APIs.
# ---------------------------------------------------------------------------
resource "kubernetes_secret_v1" "api_key" {
  metadata {
    name      = "benchmark-key-${count.index}"
    namespace = var.namespace
  }

  type = "Opaque"
  data = {
    key = "benchmark-key-${count.index}"
  }

  count      = var.middlewares.auth.type == "token_iac" ? var.middlewares.auth.app_count : 0
  depends_on = [kubernetes_namespace.traefik]
}

resource "kubectl_manifest" "managed_app" {
  yaml_body = <<YAML
apiVersion: hub.traefik.io/v1alpha1
kind: ManagedApplication
metadata:
  name: benchmark-app-${count.index}
  namespace: ${var.namespace}
spec:
  appId: benchmark-app-${count.index}
  apiKeys:
  - secretName: benchmark-key-${count.index}
    title: benchmark-key-${count.index}
YAML

  count      = var.middlewares.auth.type == "token_iac" ? var.middlewares.auth.app_count : 0
  depends_on = [kubernetes_secret_v1.api_key, helm_release.traefik]
}

resource "kubectl_manifest" "managed_subscription" {
  yaml_body = <<YAML
apiVersion: hub.traefik.io/v1alpha1
kind: ManagedSubscription
metadata:
  name: benchmark-subscription
  namespace: ${var.namespace}
spec:
  managedApplications:
${join("", [for i in range(var.middlewares.auth.app_count) : "  - name: benchmark-app-${i}\n"])}  apis:
${join("", [for i in range(var.route_count) : "  - name: benchmark-api-${i}\n"])}YAML

  count      = var.middlewares.auth.type == "token_iac" ? 1 : 0
  depends_on = [kubectl_manifest.managed_app, kubectl_manifest.hub_api]
}

# ---------------------------------------------------------------------------
# Hub API Management — API + APIVersion + APIRateLimit
# Hub applies rate limits via APIRateLimit selector, not IngressRoute middleware.
# ---------------------------------------------------------------------------
resource "kubectl_manifest" "api_rate_limit" {
  yaml_body = <<YAML
apiVersion: hub.traefik.io/v1alpha1
kind: APIRateLimit
metadata:
  name: rate-limit
  namespace: ${var.namespace}
spec:
  limit: ${var.middlewares.rate_limit.rate}
  period: ${var.middlewares.rate_limit.per}s
  everyone: true
  apiSelector:
    matchLabels:
      app: benchmark
YAML

  count      = var.middlewares.rate_limit.enabled ? 1 : 0
  depends_on = [helm_release.traefik]
}

resource "kubectl_manifest" "hub_api" {
  yaml_body = <<YAML
apiVersion: hub.traefik.io/v1alpha1
kind: API
metadata:
  name: benchmark-api-${count.index}
  namespace: ${var.namespace}
  labels:
    app: benchmark
spec:
  versions:
  - name: v1
YAML

  count      = local.needs_hub_api ? var.route_count : 0
  depends_on = [helm_release.traefik]
}

resource "kubectl_manifest" "hub_api_version" {
  yaml_body = <<YAML
apiVersion: hub.traefik.io/v1alpha1
kind: APIVersion
metadata:
  name: benchmark-api-${count.index}-v1
  namespace: ${var.namespace}
spec:
  release: 1.0.0
  title: API ${count.index}
YAML

  count      = local.needs_hub_api ? var.route_count : 0
  depends_on = [kubectl_manifest.hub_api]
}
