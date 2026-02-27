provider "google" {
  project     = var.gcp_project
  region      = var.cluster_location
  credentials = var.gcp_credentials != "" ? var.gcp_credentials : null
}
