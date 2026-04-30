# environments/dev/backend.tf
#
# Remote state in GCS.
# Before running terraform init, create the bucket:
#
#   gsutil mb -p YOUR_PROJECT -l us-central1 gs://YOUR_BUCKET_NAME
#   gsutil versioning set on gs://YOUR_BUCKET_NAME
#   gsutil uniformbucketlevelaccess set on gs://YOUR_BUCKET_NAME
#
# The bucket should have:
#   - Versioning enabled (allows state rollback)
#   - Uniform bucket-level access (no ACLs)
#   - CMEK encryption (recommended for production)
#   - Access restricted to the Terraform service account only
#
# State locking: GCS backend uses native object locks — no separate
# DynamoDB table needed (unlike AWS S3 backend).

terraform {
  backend "gcs" {
    # Replace with your actual bucket name.
    # Cannot use variables here — backend config is resolved before
    # variable interpolation. Use -backend-config flag instead:
    #   terraform init -backend-config="bucket=your-bucket-name"
    bucket = "terraform-state-bucket-claude"
    prefix = "lab1-vpc/dev"
    # State file will be at:
    # gs://YOUR_BUCKET/lab1-vpc/dev/default.tfstate
  }

  required_version = ">= 1.5"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 5.0, < 6.0"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = "us-central1"

  # Recommended: use Application Default Credentials.
  # Run: gcloud auth application-default login
  # Or set GOOGLE_APPLICATION_CREDENTIALS env var to a service account key.
  # Never hardcode credentials in provider config.
}
