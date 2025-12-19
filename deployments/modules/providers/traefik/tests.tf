# module "tests" {
#   source           = "../dependencies/k6/tests"
#   namespace        = var.namespace
#   middleware       = var.middleware
#   service          = var.service
#   route_count      = var.route_count

#   depends_on = [kubernetes_namespace.traefik]
# }

# module "scenarios" {
#   source    = "../dependencies/k6/scenarios"
#   namespace = var.namespace

#   depends_on = [kubernetes_namespace.traefik]
# }

# resource "kubernetes_config_map" "auth-configmap" {
#   metadata {
#     name      = "auth-configmap"
#     namespace = var.namespace
#   }

#   data = {
#     "auth.js" = <<EOF
# const generateKeys = (keyCount) => [];
# export { generateKeys };
# EOF
#   }

#   depends_on = [kubernetes_namespace.traefik]
# }