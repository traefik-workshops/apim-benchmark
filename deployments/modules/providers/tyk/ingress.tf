locals {
  is_auth_enabled = var.middlewares.auth.type != "disabled"
  is_jwt_auth     = contains(["jwt_hmac", "jwt_keycloak"], var.middlewares.auth.type)
  is_token_auth   = contains(["token_postgres", "token_iac"], var.middlewares.auth.type)
  # Build API definition JSON files for each route
  api_definitions = {
    # Note: Terraform's merge() coerces booleans to strings in mixed-type maps.
    # The replace() calls restore proper boolean JSON types for Tyk's strict parser.
    for i in range(var.route_count) : "api-${i}.json" => replace(replace(replace(jsonencode(merge(
      {
        name               = "api-${i}"
        slug               = "api-${i}"
        api_id             = "api-${i}"
        org_id             = "default"
        active             = true
        use_keyless        = local.is_auth_enabled ? false : true
        disable_quota      = var.middlewares.quota.enabled ? false : true
        disable_rate_limit = var.middlewares.rate_limit.enabled ? false : true

        proxy = {
          target_url           = "http://fortio-${i % var.service.count}.${var.namespace}.svc:8080"
          listen_path          = "/api-${i}"
          strip_listen_path    = true
          preserve_host_header = false
        }

        # version_data — header transforms live inside the version definition
        # (global_headers / global_response_headers on the VersionInfo struct).
        version_data = {
          default_version = "Default"
          not_versioned   = true
          versions = {
            Default = {
              name                           = "Default"
              use_extended_paths             = true
              global_headers                 = var.middlewares.headers.request.set
              global_headers_remove          = var.middlewares.headers.request.remove
              global_response_headers        = var.middlewares.headers.response.set
              global_response_headers_remove = var.middlewares.headers.response.remove
            }
          }
        }
      },

      # --- Auth (API Key) — token_postgres / token_iac -----------------------
      local.is_token_auth ? {
        auth = {
          auth_header_name = "Authorization"
        }
      } : {},

      # --- Auth (JWT HMAC) ---------------------------------------------------
      var.middlewares.auth.type == "jwt_hmac" ? {
        enable_jwt              = true
        jwt_signing_method      = "hmac"
        jwt_identity_base_field = "sub"
        jwt_source              = base64encode("topsecretpassword-benchmark-hmac")
        jwt_policy_field_name   = "pol"
        jwt_default_policies    = "__JWT_POLICIES_PLACEHOLDER__"
      } : {},

      # --- Auth (JWT Keycloak RSA) -------------------------------------------
      var.middlewares.auth.type == "jwt_keycloak" ? {
        enable_jwt              = true
        jwt_signing_method      = "rsa"
        jwt_identity_base_field = "sub"
        jwt_source              = "http://keycloak-service.dependencies.svc:8080/realms/traefik/protocol/openid-connect/certs"
        jwt_policy_field_name   = "pol"
        jwt_default_policies    = "__JWT_POLICIES_PLACEHOLDER__"
      } : {},

      # --- Rate Limiting -----------------------------------------------------
      var.middlewares.rate_limit.enabled ? {
        global_rate_limit = {
          rate = var.middlewares.rate_limit.rate
          per  = var.middlewares.rate_limit.per
        }
      } : {},

      # --- Quota -------------------------------------------------------------
      var.middlewares.quota.enabled ? {
        quota_max          = var.middlewares.quota.rate
        quota_renewal_rate = var.middlewares.quota.per
      } : {},

      # Header manipulation is inside version_data.versions.Default above.
    )), "\"enable_jwt\":\"true\"", "\"enable_jwt\":true"), "\"enable_jwt\":\"false\"", "\"enable_jwt\":false"), "\"jwt_default_policies\":\"__JWT_POLICIES_PLACEHOLDER__\"", "\"jwt_default_policies\":[\"default-jwt-policy\"]")
  }
}

# ---------------------------------------------------------------------------
# API definitions ConfigMap (loaded by gateway from /opt/tyk-gateway/apps/)
# ---------------------------------------------------------------------------
resource "kubernetes_config_map" "tyk_api_definitions" {
  metadata {
    name      = "tyk-api-definitions"
    namespace = var.namespace
    annotations = {
      auth                   = local.is_auth_enabled ? var.middlewares.auth.type : "Off"
      rate-limiting          = var.middlewares.rate_limit.enabled ? format("%d/%d", var.middlewares.rate_limit.rate, var.middlewares.rate_limit.per) : "Off"
      quota                  = var.middlewares.quota.enabled ? format("%d/%d", var.middlewares.quota.rate, var.middlewares.quota.per) : "Off"
      open-telemetry-traces  = var.middlewares.observability.traces.enabled ? "Always" : "Off"
      open-telemetry-metrics = var.middlewares.observability.metrics.enabled ? "Pump" : "Off"
      open-telemetry-logs    = "N/A"
    }
  }

  data = local.api_definitions

  depends_on = [kubernetes_namespace.tyk]
}

# ---------------------------------------------------------------------------
# Security policies (loaded by gateway from /mnt/tyk-gateway/policies/)
# Required for JWT authentication — default policy grants API access.
# ---------------------------------------------------------------------------
resource "kubernetes_config_map" "tyk_policies" {
  metadata {
    name      = "tyk-policies"
    namespace = var.namespace
  }

  data = {
    "default-jwt-policy.json" = jsonencode({
      id                 = "default-jwt-policy"
      org_id             = "default"
      rate               = 0
      per                = 0
      quota_max          = -1
      quota_renewal_rate = 0
      name               = "Default JWT Policy"
      active             = true
      is_inactive        = false
      access_rights = { for i in range(var.route_count) : "api-${i}" => {
        api_id   = "api-${i}"
        api_name = "api-${i}"
        versions = ["Default"]
      } }
    })
  }

  count      = local.is_jwt_auth ? 1 : 0
  depends_on = [kubernetes_namespace.tyk]
}
