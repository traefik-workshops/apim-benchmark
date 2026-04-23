resource "helm_release" "gravitee-operator" {
  name       = "gravitee-operator"
  repository = "https://helm.gravitee.io"
  chart      = "gko"

  namespace = var.namespace
  atomic    = true

  values = [
    yamlencode({
      manager = {
        resources = null
        # The GKO chart puts nodeSelector on manager.pod, not manager.
        # Tolerations are on manager directly.
        pod = {
          nodeSelector = {
            node = var.taint
          }
        }
        tolerations = [{
          key      = "node"
          operator = "Equal"
          value    = var.taint
          effect   = "NoSchedule"
        }]
      }
    })
  ]

  depends_on = [helm_release.gravitee]
}

resource "kubectl_manifest" "gravitee-context" {
  yaml_body  = <<YAML
apiVersion: gravitee.io/v1alpha1
kind: ManagementContext
metadata:
  name: "gravitee-context"
  namespace: "${var.namespace}"
spec:
  baseUrl: "http://${helm_release.gravitee.name}-apim-api.${var.namespace}.svc:83"
  environmentId: "DEFAULT"
  organizationId: "DEFAULT"
  auth:
    credentials:
      username: "admin"
      password: "admin"
YAML
  depends_on = [helm_release.gravitee, helm_release.gravitee-operator]

  # Finalizer drain — the GKO admission webhook rejects deletion of this
  # context while any CR still references it via contextRef (ApiDefinition,
  # Application, Subscription). kubectl_manifest returns success from its
  # destroy as soon as the k8s API accepts the DELETE call, but those CRs
  # carry finalizers and linger in etcd until GKO processes them. Without
  # this gate, Terraform races past the api[*] destroys into this context
  # destroy and the webhook fails with "N APIs are relying on this context".
  #
  # Destroy ordering: Terraform reverses create order, so api[*],
  # benchmark_app, and jwt_subscription (which all depend on this context
  # via wait_apim_api) are destroyed BEFORE this resource. By the time
  # this destroy-time provisioner runs, their DELETE calls have already
  # been issued; we just wait for the finalizers to actually complete
  # before Terraform issues this context's DELETE.
  provisioner "local-exec" {
    when    = destroy
    command = <<-EOT
      set -u
      for kind in apidefinitions applications subscriptions; do
        kubectl wait --for=delete "$${kind}.gravitee.io" \
          --all -n "${self.namespace}" \
          --timeout=300s 2>/dev/null || true
      done
    EOT
  }
}
