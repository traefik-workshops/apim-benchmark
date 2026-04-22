locals {
  # Gravitee supports: token_postgres (API_KEY), jwt_hmac, jwt_keycloak
  # token_iac is N/A for Gravitee
  is_auth_enabled = contains(["token_postgres", "jwt_hmac", "jwt_keycloak"], var.middlewares.auth.type)
  is_jwt_auth     = contains(["jwt_hmac", "jwt_keycloak"], var.middlewares.auth.type)
  # Gravitee only supports token_postgres (API_KEY via Portal subscriptions)
  # token_iac is N/A for Gravitee — falls through to KEY_LESS
  is_token_auth    = var.middlewares.auth.type == "token_postgres"
  has_req_headers  = length(var.middlewares.headers.request.set) > 0 || length(var.middlewares.headers.request.remove) > 0
  has_resp_headers = length(var.middlewares.headers.response.set) > 0 || length(var.middlewares.headers.response.remove) > 0
  has_headers      = local.has_req_headers || local.has_resp_headers
  has_middlewares  = local.is_auth_enabled || var.middlewares.rate_limit.enabled || var.middlewares.quota.enabled || local.has_headers

  # Application clientId must match a JWT claim that Gravitee uses for
  # subscription lookup.  Gravitee resolves client_id from the JWT using
  # the fallback chain: azp → aud → client_id.
  #   jwt_hmac      — k6 generates tokens with client_id = "benchmark-app"
  #   jwt_keycloak  — Keycloak tokens carry azp = "traefik" (the OIDC client)
  jwt_app_client_id = (
    var.middlewares.auth.type == "jwt_keycloak" ? "traefik" : "benchmark-app"
  )

  # Map auth type to Gravitee plan security type
  plan_security = (
    local.is_jwt_auth ? "JWT" :
    local.is_token_auth ? "API_KEY" :
    "KEY_LESS"
  )

  # JWT security definition JSON for Gravitee JWT plans.
  # clientIdClaim is set explicitly to avoid the default azp→aud→client_id
  # fallback chain which can match the wrong claim (e.g. aud often contains
  # a resource URL, not a client identifier — see gravitee-io/issues#3835).
  jwt_security_definition = (
    var.middlewares.auth.type == "jwt_hmac"
    ? jsonencode({
      signature         = "HMAC_HS256"
      publicKeyResolver = "GIVEN_KEY"
      resolverParameter = "topsecretpassword-benchmark-hmac"
      clientIdClaim     = "client_id"
    })
    : var.middlewares.auth.type == "jwt_keycloak"
    ? jsonencode({
      signature         = "RSA_RS256"
      publicKeyResolver = "JWKS_URL"
      resolverParameter = "http://keycloak-service.dependencies.svc:8080/realms/traefik/protocol/openid-connect/certs"
      clientIdClaim     = "azp"
    })
    : ""
  )
}

# ---------------------------------------------------------------------------
# Readiness gate — the GKO admission webhook validates every ApiDefinition
# by round-tripping through http://gravitee-apim-api:83/management/.../import-crd
# On a cold apply the apim-api pod has usually just become Ready (pod-level
# TCP check) but its Spring Boot management endpoint is still initialising,
# so the very first kubectl_manifest.api fails with "connection refused".
#
# We poll the Management API from inside the cluster using an ephemeral curl
# pod until it responds with 2xx, then let the ApiDefinition apply.
# ---------------------------------------------------------------------------
resource "null_resource" "wait_apim_api" {
  triggers = {
    # Re-run on every apply so we don't cache a stale "ready" outcome from a
    # previous terraform run.
    helm_release = helm_release.gravitee.id
    run_id       = timestamp()
  }

  provisioner "local-exec" {
    interpreter = ["bash", "-c"]
    command     = <<-EOT
      set -e
      NS=${var.namespace}
      echo "Waiting for Gravitee APIM Management API to accept requests..."
      # The webhook does a PUT to .../apis/import-crd. That endpoint returns
      # 4xx on the probe payload (e.g. "invalid body") — we treat ANY HTTP
      # response as "server is up" since the original failure mode is
      # connection-refused / 5xx. Once TCP is accepting and the server
      # routes requests, the admission webhook succeeds.
      for i in $(seq 1 60); do
        code=$(kubectl -n "$NS" run gravitee-healthcheck-$$ \
          --rm -i --restart=Never --quiet \
          --image=curlimages/curl:8.6.0 -- \
          curl -s -o /dev/null -w "%%{http_code}" -m 5 -u admin:admin \
          "http://gravitee-apim-api.$NS.svc:83/management/v2/environments/DEFAULT" \
          2>/dev/null || echo 000)
        case "$code" in
          2??|400|401|403|404)
            echo "Management API ready (HTTP $code) after $((i*5))s"
            exit 0
            ;;
        esac
        sleep 5
      done
      echo "Management API did not become ready within 300s (last code: $code)"
      exit 1
    EOT
  }

  depends_on = [helm_release.gravitee, helm_release.gravitee-operator, kubectl_manifest.gravitee-context]
}

# ---------------------------------------------------------------------------
# Single API definition — adjusts plan security and flow policies based on
# middleware configuration. Using one resource avoids GKO operator race
# conditions that occur when destroying + recreating with the same k8s name.
# ---------------------------------------------------------------------------
resource "kubectl_manifest" "api" {
  yaml_body  = <<YAML
apiVersion: gravitee.io/v1alpha1
kind: ApiDefinition
metadata:
  name: "api-${count.index}"
  namespace: "${var.namespace}"
  annotations:
    auth: "${local.is_auth_enabled ? var.middlewares.auth.type : "Off"}"
    rate-limiting: "${var.middlewares.rate_limit.enabled ? format("%d/%d", var.middlewares.rate_limit.rate, var.middlewares.rate_limit.per) : "Off"}"
    quota: "${var.middlewares.quota.enabled ? format("%d/%d", var.middlewares.quota.rate, var.middlewares.quota.per) : "Off"}"
    open-telemetry-traces: "N/A"
    open-telemetry-metrics: "N/A"
    open-telemetry-logs: "N/A"
spec:
  name: "api-${count.index}"
  contextRef:
    name: "gravitee-context"
    namespace: "${var.namespace}"
  version: "1.0"
  description: "api-${count.index}"
  visibility: "PUBLIC"
  lifecycle_state: "PUBLISHED"
  plans:
  - name: "${local.plan_security}"
    description: "${local.plan_security}"
    security: "${local.plan_security}"
%{if local.is_jwt_auth~}
    securityDefinition: '${local.jwt_security_definition}'
%{endif~}
%{if local.has_middlewares~}
    flows:
    - path-operator:
        path: "/"
        operator: "STARTS_WITH"
      pre:
      - name: "Rate limit"
        enabled: ${var.middlewares.rate_limit.enabled}
        policy: "rate-limit"
        configuration:
          addHeaders: false
          async: false
          rate:
            periodTime: ${var.middlewares.rate_limit.per}
            limit: ${var.middlewares.rate_limit.rate}
            periodTimeUnit: "SECONDS"
      - name: "Quota"
        enabled: ${var.middlewares.quota.enabled}
        policy: "quota"
        configuration:
          addHeaders: true
          async: false
          quota:
            periodTime: ${floor(var.middlewares.quota.per / 3600)}
            limit: ${var.middlewares.quota.rate}
            periodTimeUnit: "HOURS"
%{if local.has_req_headers~}
      - name: "Request Headers"
        enabled: true
        policy: "transform-headers"
        configuration:
          scope: "REQUEST"
%{if length(var.middlewares.headers.request.set) > 0~}
          addHeaders:
%{for name, value in var.middlewares.headers.request.set~}
          - name: "${name}"
            value: "${value}"
%{endfor~}
%{endif~}
%{if length(var.middlewares.headers.request.remove) > 0~}
          removeHeaders:
%{for name in var.middlewares.headers.request.remove~}
          - "${name}"
%{endfor~}
%{endif~}
%{endif~}
%{if local.has_resp_headers~}
      post:
      - name: "Response Headers"
        enabled: true
        policy: "transform-headers"
        configuration:
          scope: "RESPONSE"
%{if length(var.middlewares.headers.response.set) > 0~}
          addHeaders:
%{for name, value in var.middlewares.headers.response.set~}
          - name: "${name}"
            value: "${value}"
%{endfor~}
%{endif~}
%{if length(var.middlewares.headers.response.remove) > 0~}
          removeHeaders:
%{for name in var.middlewares.headers.response.remove~}
          - "${name}"
%{endfor~}
%{endif~}
%{endif~}
%{endif~}
  proxy:
    virtual_hosts:
    - path: "/api-${count.index}"
    groups:
    - endpoints:
      - name: "Default"
        target: "http://fortio-${count.index % var.service.count}.${var.namespace}.svc:8080"
YAML
  count      = var.route_count
  depends_on = [null_resource.wait_apim_api]
}

# ---------------------------------------------------------------------------
# JWT subscription setup via GKO CRDs — creates an Application with a known
# client_id and Subscription resources linking it to each JWT plan. This
# ensures the gateway syncs subscriptions via Kubernetes (not just the
# Management API).
# ---------------------------------------------------------------------------
resource "kubectl_manifest" "benchmark_app" {
  count = local.is_jwt_auth ? 1 : 0

  yaml_body = <<YAML
apiVersion: gravitee.io/v1alpha1
kind: Application
metadata:
  name: "benchmark-app"
  namespace: "${var.namespace}"
spec:
  contextRef:
    name: "gravitee-context"
    namespace: "${var.namespace}"
  name: "benchmark-app"
  description: "Benchmark application for JWT authentication"
  settings:
    app:
      type: "SIMPLE"
      clientId: "${local.jwt_app_client_id}"
YAML

  depends_on = [null_resource.wait_apim_api]
}

resource "kubectl_manifest" "jwt_subscription" {
  count = local.is_jwt_auth ? var.route_count : 0

  yaml_body = <<YAML
apiVersion: gravitee.io/v1alpha1
kind: Subscription
metadata:
  name: "jwt-sub-api-${count.index}"
  namespace: "${var.namespace}"
spec:
  api:
    name: "api-${count.index}"
    namespace: "${var.namespace}"
    kind: ApiDefinition
  application:
    name: "benchmark-app"
    namespace: "${var.namespace}"
    kind: Application
  plan: "JWT"
YAML

  depends_on = [kubectl_manifest.api, kubectl_manifest.benchmark_app]
}
