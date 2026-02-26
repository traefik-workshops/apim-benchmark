resource "kubernetes_deployment" "fortio" {
  metadata {
    name      = "fortio-upstream"
    namespace = var.namespace
  }
  spec {
    selector {
      match_labels = {
        app = "fortio"
      }
    }
    template {
      metadata {
        labels = {
          app = "fortio"
        }
      }
      spec {
        container {
          image = "fortio/fortio"
          name  = "fortio"
          args  = ["server"]
          port {
            container_port = 8080
            protocol       = "TCP"
          }
        }
        toleration {
          key      = "node"
          operator = "Equal"
          value    = var.taint
          effect   = "NoSchedule"
        }
      }
    }
  }
}

resource "kubernetes_service_v1" "fortio" {
  metadata {
    name      = "fortio-${count.index}"
    namespace = var.namespace
    labels = {
      app = "fortio"
    }
  }
  spec {
    type = "ClusterIP"
    selector = {
      app = "fortio"
    }
    port {
      name        = "http"
      port        = 8080
      protocol    = "TCP"
      target_port = 8080
    }
  }

  count = var.service_count
}

