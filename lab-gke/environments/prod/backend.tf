# environments/prod/backend.tf
#
# Remote state in GCS.
# Pass bucket at init time — backend blocks cannot use variables:
#   terraform init -backend-config="bucket=your-tf-state-bucket"

terraform {
  backend "gcs" {
    bucket = "terraform-state-bucket-claude"
    prefix = "lab-gke/prod"
  }

  required_version = ">= 1.5"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 5.0, < 6.0"
    }
    google-beta = {
      source  = "hashicorp/google-beta"
      version = ">= 5.0, < 6.0"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

provider "google-beta" {
  project = var.project_id
  region  = var.region
}
