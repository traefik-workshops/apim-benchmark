# resource "helm_release" "opentelemetry-collector" {
#   name       = "opentelemetry-collector"
#   repository = "https://open-telemetry.github.io/opentelemetry-helm-charts"
#   chart      = "opentelemetry-collector"
#   version    = "0.62.0"

#   namespace = var.namespace
#   atomic    = true

#   values = [
#     yamlencode({
#       mode = "deployment"
#       config = {
#         receivers = {
#           otlp = {
#             protocols = {
#               http = {
#                 endpoint = "0.0.0.0:4318"
#               }
#               grpc = {
#                 endpoint = "0.0.0.0:4317"
#               }
#             }
#           }
#         }
#         exporters = {}
#         service = {
#           pipelines = {
#             traces = {
#               receivers = ["otlp"]
#               processors = ["batch"]
#               exporters = []
#             }
#           }
#         }
#       }
#       tolerations = local.tolerations
#     })
#   ]

#   depends_on = [kubernetes_namespace.dependencies]
# }
