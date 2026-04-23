# ---------------------------------------------------------------------------
# Single source of truth for every Helm chart version pinned by this stack.
#
# Gateway image tags are separate (they come from apim_providers.<x>.version
# in the tfvars) because image and chart release cadences differ across
# projects. These are the chart versions — bump here when you want a newer
# chart, and re-verify in k3d with "make validate-test" before shipping to
# cloud.
#
# The image tag and chart version for Envoy Gateway happen to march in lock-
# step (the chart IS versioned the same as the app), so the module for that
# one provider reuses var.gateway_version instead of taking a separate
# chart_version.
# ---------------------------------------------------------------------------
locals {
  chart_versions = {
    dep_traefik = "39.0.8" # dependencies-namespace Traefik ingress
    traefik     = "39.0.8" # provider-under-test Traefik chart (Hub or OSS)
    kong        = "0.24.0" # kong/ingress Helm chart (Kong Gateway 3.9)
    tyk         = "5.1.1"  # tyk-oss chart
    gravitee    = "4.11.4" # gravitee/apim chart — also the app version
    # envoygateway chart version = image tag; supplied via
    # apim_providers.envoygateway.version in tfvars.
  }
}
