terraform {
  required_providers {
    kubectl = {
      source = "alekc/kubectl"
      version = ">= 2.1.3"
    }
  }
}

provider "helm" {
  kubernetes = {
    config_path    = var.kubernetes_config_path
    config_context = var.kubernetes_config_context
  }
}

provider "kubernetes" {
  config_path    = var.kubernetes_config_path
  config_context = var.kubernetes_config_context
}

provider "kubectl" {
  config_path    = var.kubernetes_config_path
  config_context = var.kubernetes_config_context
}