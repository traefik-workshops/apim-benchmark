# ---------------------------------------------------------------------------
# Tyk OSS Metrics
# ---------------------------------------------------------------------------
# Tyk OSS does not expose a native Prometheus metrics endpoint.
# Prometheus metrics require the Tyk Pump component (disabled in this setup)
# configured with the "prometheus" pump backend.
#
# Current setup: enable_analytics is toggled via var.middlewares.observability.
# metrics.enabled, which feeds Tyk's internal Redis-based analytics.
#
# To enable Prometheus scraping, either:
#   1. Enable Tyk Pump (global.components.pump = true) with prometheus pump
#   2. Use a Prometheus exporter sidecar
#   3. Use OTLP metrics export via OpenTelemetry (when available)
# ---------------------------------------------------------------------------
