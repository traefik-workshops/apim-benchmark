variable "namespace" {
  type = string
}

variable "taint" {
  type = string
}
variable "deployment" {
  type = object({
    type          = string
    replica_count = number
  })
}

variable "service" {
  type = object({
    type                    = string
    count                   = number
    external_traffic_policy = string
  })
}

variable "route_count" {
  type = number
}
