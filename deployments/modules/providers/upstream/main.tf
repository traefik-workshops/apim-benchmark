resource "kubernetes_namespace_v1" "upstream" {
  metadata {
    name = var.namespace
  }
}

module "upstream" {
  source        = "../../dependencies/upstream"
  namespace     = var.namespace
  taint         = var.taint
  service_count = var.service.count

  depends_on = [kubernetes_namespace_v1.upstream]
}

module "scenarios" {
  source    = "../../dependencies/k6/scenarios"
  namespace = var.namespace

  depends_on = [module.upstream]
}

resource "kubernetes_config_map" "tests-configmap" {
  metadata {
    name      = "tests-configmap"
    namespace = var.namespace
  }

  data = {
    "tests.js" = <<EOF
const addTestInfoMetrics = () => {};
const getAuth = () => false;
const getAuthType = () => "";
const generateJWTRSAKeys = () => [];
const generateJWTHMACKeys = () => [];
const getRouteCount = () => ${var.route_count};
const getHostCount = () => ${var.service.count};

export { getAuth, getAuthType, getRouteCount, getHostCount, generateJWTRSAKeys, generateJWTHMACKeys, addTestInfoMetrics };

EOF
  }

  depends_on = [module.upstream]
}

resource "kubernetes_config_map" "auth-configmap" {
  metadata {
    name      = "auth-configmap"
    namespace = var.namespace
  }

  data = {
    "auth.js" = <<EOF
const generateKeys = (keyCount) => [];
export { generateKeys };
EOF
  }

  depends_on = [module.upstream]
}
