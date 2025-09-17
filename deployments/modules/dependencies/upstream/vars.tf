variable "namespace" {
  type    = string
  default = "upstream"
}

variable "taint" {
  type = string
}

variable "service_count" {
  type = number
}
