# ---------------------------------------------------------------------------
# EnvoyProxy — custom proxy configuration (strips default resource limits)
# Conditionally includes telemetry when observability middlewares are enabled.
# ---------------------------------------------------------------------------
locals {
  tracing_enabled  = var.middlewares.observability.traces.enabled
  metrics_enabled  = var.middlewares.observability.metrics.enabled
  has_telemetry    = local.tracing_enabled || local.metrics_enabled
  has_req_headers  = length(var.middlewares.headers.request.set) > 0 || length(var.middlewares.headers.request.remove) > 0
  has_resp_headers = length(var.middlewares.headers.response.set) > 0 || length(var.middlewares.headers.response.remove) > 0
  has_headers      = local.has_req_headers || local.has_resp_headers

  logs_enabled          = var.middlewares.observability.logs.enabled
  has_telemetry_or_logs = local.has_telemetry || local.logs_enabled

  # Build the telemetry block as raw YAML to inject into the EnvoyProxy spec.
  # All signals exported via OTLP to the OpenTelemetry Collector.
  telemetry_block = local.has_telemetry_or_logs ? join("\n", compact([
    "  telemetry:",
    local.tracing_enabled ? "    tracing:\n      provider:\n        type: OpenTelemetry\n        host: opentelemetry-collector.dependencies.svc\n        port: 4317\n      customTags:\n        service.name:\n          type: Literal\n          literal:\n            value: envoygateway" : "",
    local.metrics_enabled ? "    metrics:\n      prometheus:\n        disable: true\n      sinks:\n      - type: OpenTelemetry\n        openTelemetry:\n          host: opentelemetry-collector.dependencies.svc\n          port: 4317" : "",
    local.logs_enabled ? "    accessLog:\n      settings:\n      - sinks:\n        - type: OpenTelemetry\n          openTelemetry:\n            host: opentelemetry-collector.dependencies.svc\n            port: 4317\n            resources:\n              service.name: envoygateway" : "",
  ])) : ""
}

resource "kubectl_manifest" "envoyproxy" {
  yaml_body = <<YAML
apiVersion: gateway.envoyproxy.io/v1alpha1
kind: EnvoyProxy
metadata:
  name: custom-proxy
  namespace: ${var.namespace}
spec:
  provider:
    type: Kubernetes
    kubernetes:
      envoyDeployment:
        container:
%{if var.deployment.resources != null~}
          resources:
            requests:
              cpu: ${var.deployment.resources.requests.cpu}
              memory: ${var.deployment.resources.requests.memory}
            limits:
              cpu: ${var.deployment.resources.limits.cpu}
              memory: ${var.deployment.resources.limits.memory}
%{else~}
          resources: {}
%{endif~}
        pod:
          nodeSelector:
            node: ${var.taint}
          tolerations:
          - key: node
            operator: Equal
            value: ${var.taint}
            effect: NoSchedule
      envoyService:
        type: ClusterIP
${local.telemetry_block}
YAML

  depends_on = [helm_release.envoygateway]
}

# ---------------------------------------------------------------------------
# GatewayClass + Gateway
# ---------------------------------------------------------------------------
resource "kubectl_manifest" "gatewayclass" {
  yaml_body = <<YAML
apiVersion: gateway.networking.k8s.io/v1
kind: GatewayClass
metadata:
  name: envoy-gateway
spec:
  controllerName: gateway.envoyproxy.io/gatewayclass-controller
  parametersRef:
    group: gateway.envoyproxy.io
    kind: EnvoyProxy
    name: custom-proxy
    namespace: ${var.namespace}
YAML

  depends_on = [helm_release.envoygateway, kubectl_manifest.envoyproxy]
}

resource "kubectl_manifest" "gateway" {
  yaml_body = <<YAML
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: envoy-gateway
  namespace: ${var.namespace}
spec:
  gatewayClassName: envoy-gateway
  listeners:
  - name: http
    protocol: HTTP
    port: 8080
    allowedRoutes:
      namespaces:
        from: Same
%{if var.middlewares.tls.enabled~}
  - name: https
    protocol: HTTPS
    port: 8443
    tls:
      mode: Terminate
      certificateRefs:
      - kind: Secret
        name: gateway-tls-cert
    allowedRoutes:
      namespaces:
        from: Same
%{endif~}
YAML

  depends_on = [kubectl_manifest.gatewayclass]
}

# ---------------------------------------------------------------------------
# HTTPRoutes — API routing definitions (with optional header manipulation)
# ---------------------------------------------------------------------------
resource "kubectl_manifest" "api" {
  yaml_body = <<YAML
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: api-${count.index}
  namespace: ${var.namespace}
spec:
  parentRefs:
  - name: envoy-gateway
    namespace: ${var.namespace}
  rules:
  - matches:
    - path:
        type: PathPrefix
        value: /api-${count.index}
%{if local.has_headers~}
    filters:
%{if local.has_req_headers~}
    - type: RequestHeaderModifier
      requestHeaderModifier:
%{if length(var.middlewares.headers.request.set) > 0~}
        set:
%{for name, value in var.middlewares.headers.request.set~}
        - name: ${name}
          value: "${value}"
%{endfor~}
%{endif~}
%{if length(var.middlewares.headers.request.remove) > 0~}
        remove:
%{for name in var.middlewares.headers.request.remove~}
        - ${name}
%{endfor~}
%{endif~}
%{endif~}
%{if local.has_resp_headers~}
    - type: ResponseHeaderModifier
      responseHeaderModifier:
%{if length(var.middlewares.headers.response.set) > 0~}
        set:
%{for name, value in var.middlewares.headers.response.set~}
        - name: ${name}
          value: "${value}"
%{endfor~}
%{endif~}
%{if length(var.middlewares.headers.response.remove) > 0~}
        remove:
%{for name in var.middlewares.headers.response.remove~}
        - ${name}
%{endfor~}
%{endif~}
%{endif~}
%{endif~}
    backendRefs:
    - name: fortio-${count.index % var.service.count}
      port: 8080
YAML

  count      = var.route_count
  depends_on = [kubectl_manifest.gateway]
}
