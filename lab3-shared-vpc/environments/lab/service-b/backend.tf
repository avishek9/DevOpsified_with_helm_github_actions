# environments/lab/service-b/backend.tf
terraform {
  backend "gcs" {
    bucket = "YOUR_STATE_BUCKET"
    prefix = "lab3-shared-vpc/service-b"
  }
  required_version = ">= 1.5"
  required_providers {
    google = { source = "hashicorp/google"; version = ">= 5.0, < 6.0" }
  }
}
provider "google" { project = var.service_project_id; region = var.region }
