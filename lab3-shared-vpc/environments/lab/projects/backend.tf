# environments/lab/projects/backend.tf
#
# This workspace runs FIRST — before host or service project workspaces.
# It creates the three projects that the rest of the lab depends on.
#
# Apply order for the full lab:
#   1. environments/lab/projects   ← creates host + service projects
#   2. environments/lab/host       ← creates Shared VPC, subnets, IAM
#   3. environments/lab/service-a  ← creates GKE cluster
#   3. environments/lab/service-b  ← IAM binding verification

terraform {
  backend "gcs" {
    bucket = "YOUR_STATE_BUCKET"
    prefix = "lab3-shared-vpc/projects"
  }
  required_version = ">= 1.5"
  required_providers {
    google = { source = "hashicorp/google"; version = ">= 5.0, < 6.0" }
  }
}

# The provider here authenticates as a user or SA with org-level
# projectCreator permission — more privileged than the per-project SAs
# used in the host/service environments.
provider "google" {}
