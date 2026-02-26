locals {
  auth_enabled = var.middlewares.auth.type != "disabled"

  # Map auth type → Kong plugin name
  auth_plugin_name = {
    "token_iac"      = "key-auth"
    "token_postgres" = "key-auth"
    "jwt_hmac"       = "jwt"
    "jwt_keycloak"   = "jwt"
  }

  plugin_list = compact([
    local.auth_enabled ? lookup(local.auth_plugin_name, var.middlewares.auth.type, "") : "",
    var.middlewares.rate_limit.enabled || var.middlewares.quota.enabled ? "rate-limiting" : "",
    length(var.middlewares.headers.request.set) > 0 || length(var.middlewares.headers.request.remove) > 0 ? "request-transformer" : "",
    length(var.middlewares.headers.response.set) > 0 || length(var.middlewares.headers.response.remove) > 0 ? "response-transformer" : "",
    var.middlewares.observability.metrics.enabled ? "prometheus" : "",
    var.middlewares.observability.traces.enabled ? "opentelemetry" : "",
  ])
  p       = join(",", local.plugin_list)
  plugins = length(local.plugin_list) == 0 ? "" : (local.p == null ? "" : local.p)
}

# ---------------------------------------------------------------------------
# Auth — key-auth plugin (token_iac / token_postgres)
# ---------------------------------------------------------------------------
resource "kubectl_manifest" "auth-key-auth-plugin" {
  yaml_body = <<YAML
apiVersion: configuration.konghq.com/v1
kind: KongPlugin
metadata:
  name: key-auth
  namespace: "${var.namespace}"
plugin: key-auth
config:
   key_names:
   - Authorization
YAML

  count      = contains(["token_iac", "token_postgres"], var.middlewares.auth.type) ? 1 : 0
  depends_on = [helm_release.kong]
}

# KongConsumer + key-auth credentials (token_iac only — static keys via TF)
resource "kubectl_manifest" "kong-consumer" {
  yaml_body = <<YAML
apiVersion: configuration.konghq.com/v1
kind: KongConsumer
metadata:
  name: app-${count.index}
  namespace: "${var.namespace}"
  annotations:
    kubernetes.io/ingress.class: kong
username: app-${count.index}
credentials:
- app-${count.index}-key-auth
YAML

  count      = var.middlewares.auth.type == "token_iac" ? var.middlewares.auth.app_count : 0
  depends_on = [helm_release.kong, kubernetes_secret_v1.kong-key-auth]
}

resource "kubernetes_secret_v1" "kong-key-auth" {
  metadata {
    name      = "app-${count.index}-key-auth"
    namespace = var.namespace
    labels = {
      "konghq.com/credential" = "key-auth"
    }
  }

  data = {
    key = "benchmark-key-${count.index}"
  }

  count      = var.middlewares.auth.type == "token_iac" ? var.middlewares.auth.app_count : 0
  depends_on = [kubernetes_namespace.kong]
}

# ---------------------------------------------------------------------------
# Auth — JWT plugin (jwt_hmac / jwt_keycloak)
# ---------------------------------------------------------------------------
resource "kubectl_manifest" "auth-jwt-plugin" {
  yaml_body = <<YAML
apiVersion: configuration.konghq.com/v1
kind: KongPlugin
metadata:
  name: jwt
  namespace: "${var.namespace}"
plugin: jwt
config:
  uri_param_names: []
  header_names:
  - Authorization
  claims_to_verify:
  - exp
YAML

  count      = contains(["jwt_hmac", "jwt_keycloak"], var.middlewares.auth.type) ? 1 : 0
  depends_on = [helm_release.kong]
}

# JWT consumer + HMAC credential (jwt_hmac)
resource "kubectl_manifest" "kong-jwt-consumer" {
  yaml_body = <<YAML
apiVersion: configuration.konghq.com/v1
kind: KongConsumer
metadata:
  name: jwt-user-${count.index}
  namespace: "${var.namespace}"
  annotations:
    kubernetes.io/ingress.class: kong
username: jwt-user-${count.index}
credentials:
- jwt-user-${count.index}-jwt
YAML

  count      = var.middlewares.auth.type == "jwt_hmac" ? var.middlewares.auth.app_count : 0
  depends_on = [helm_release.kong, kubernetes_secret_v1.kong-jwt-hmac]
}

resource "kubernetes_secret_v1" "kong-jwt-hmac" {
  metadata {
    name      = "jwt-user-${count.index}-jwt"
    namespace = var.namespace
    labels = {
      "konghq.com/credential" = "jwt"
    }
  }

  data = {
    key       = "k6"
    algorithm = "HS256"
    secret    = "topsecretpassword-benchmark-hmac"
  }

  count      = var.middlewares.auth.type == "jwt_hmac" ? var.middlewares.auth.app_count : 0
  depends_on = [kubernetes_namespace.kong]
}

# JWT consumer + Keycloak RSA credential (jwt_keycloak)
resource "kubectl_manifest" "kong-jwt-keycloak-consumer" {
  yaml_body = <<YAML
apiVersion: configuration.konghq.com/v1
kind: KongConsumer
metadata:
  name: keycloak-consumer
  namespace: "${var.namespace}"
  annotations:
    kubernetes.io/ingress.class: kong
username: keycloak-consumer
credentials:
- keycloak-jwt-credential
YAML

  count      = var.middlewares.auth.type == "jwt_keycloak" ? 1 : 0
  depends_on = [helm_release.kong, kubernetes_secret_v1.kong-jwt-keycloak]
}

resource "kubernetes_secret_v1" "kong-jwt-keycloak" {
  metadata {
    name      = "keycloak-jwt-credential"
    namespace = var.namespace
    labels = {
      "konghq.com/credential" = "jwt"
    }
  }

  data = {
    key              = "http://keycloak-service.dependencies.svc:8080/realms/traefik"
    algorithm        = "RS256"
    rsa_public_key   = ""
  }

  count      = var.middlewares.auth.type == "jwt_keycloak" ? 1 : 0
  depends_on = [kubernetes_namespace.kong]
}

# ---------------------------------------------------------------------------
# Rate Limiting
# ---------------------------------------------------------------------------
resource "kubectl_manifest" "rate-limit-plugin" {
  yaml_body = <<YAML
apiVersion: configuration.konghq.com/v1
kind: KongPlugin
metadata:
  name: rate-limiting
  namespace: "${var.namespace}"
plugin: rate-limiting
config:
  ${var.middlewares.rate_limit.enabled ? "${var.middlewares.rate_limit.per <= 1 ? "second" : var.middlewares.rate_limit.per <= 60 ? "minute" : "hour"}: ${var.middlewares.rate_limit.rate}" : ""}
  ${var.middlewares.quota.enabled ? "hour: ${var.middlewares.quota.rate}" : ""}
  policy: redis
  redis_host: kong-redis
  redis_password: ${local.redis_pass}
YAML
  count      = var.middlewares.rate_limit.enabled || var.middlewares.quota.enabled ? 1 : 0
  depends_on = [helm_release.kong]
}

# ---------------------------------------------------------------------------
# Header Manipulation
# ---------------------------------------------------------------------------
resource "kubectl_manifest" "request-transformer-plugin" {
  yaml_body = <<YAML
apiVersion: configuration.konghq.com/v1
kind: KongPlugin
metadata:
  name: request-transformer
  namespace: "${var.namespace}"
plugin: request-transformer
config:
  add:
    headers:
%{for name, value in var.middlewares.headers.request.set~}
    - "${name}:${value}"
%{endfor~}
  remove:
    headers:
%{for name in var.middlewares.headers.request.remove~}
    - "${name}"
%{endfor~}
YAML

  count      = length(var.middlewares.headers.request.set) > 0 || length(var.middlewares.headers.request.remove) > 0 ? 1 : 0
  depends_on = [helm_release.kong]
}

resource "kubectl_manifest" "response-transformer-plugin" {
  yaml_body = <<YAML
apiVersion: configuration.konghq.com/v1
kind: KongPlugin
metadata:
  name: response-transformer
  namespace: "${var.namespace}"
plugin: response-transformer
config:
  add:
    headers:
%{for name, value in var.middlewares.headers.response.set~}
    - "${name}:${value}"
%{endfor~}
  remove:
    headers:
%{for name in var.middlewares.headers.response.remove~}
    - "${name}"
%{endfor~}
YAML

  count      = length(var.middlewares.headers.response.set) > 0 || length(var.middlewares.headers.response.remove) > 0 ? 1 : 0
  depends_on = [helm_release.kong]
}

# ---------------------------------------------------------------------------
# Observability — Prometheus
# ---------------------------------------------------------------------------
resource "kubectl_manifest" "prometheus-plugin" {
  yaml_body = <<YAML
apiVersion: configuration.konghq.com/v1
kind: KongPlugin
metadata:
  name: prometheus
  namespace: "${var.namespace}"
plugin: prometheus
config:
  per_consumer: true
YAML
  depends_on = [helm_release.kong]
}

# ---------------------------------------------------------------------------
# Observability — OpenTelemetry
# ---------------------------------------------------------------------------
resource "kubectl_manifest" "opentelemetry-plugin" {
  yaml_body = <<YAML
apiVersion: configuration.konghq.com/v1
kind: KongPlugin
metadata:
  name: opentelemetry
  namespace: "${var.namespace}"
plugin: opentelemetry
config:
  endpoint: http://opentelemetry-collector.dependencies.svc:4317/v1/traces
  resource_attributes:
    service.name: kong
YAML
  depends_on = [helm_release.kong]
}
