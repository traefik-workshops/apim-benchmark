variable "namespace" {
  type    = string
  default = "dependencies"
}

variable "taint" {
  type = string
}

variable "grafana" {
  type = object({
    service = object({
      type = string
    })
  })

  default = {
    service = {
      type = "ClusterIP"
    }
  }
}

variable "keycloak" {
  type = object({
    enabled = bool
  })
}
