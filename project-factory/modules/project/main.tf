# modules/project/main.tf

terraform {
  required_providers {
    google = { source = "hashicorp/google"
    version = ">= 5.0, < 6.0" }
  }
}

variable "entry"              { type = any }
variable "billing_account_id" { type = string }
variable "org_id"             { type = string; default = null }
variable "folder_id"          { type = string; default = null }

# ── Project ───────────────────────────────────────────────────────────────────

resource "google_project" "project" {
  project_id = var.entry.project.id
  name       = var.entry.project.name
  folder_id  = var.folder_id
  org_id     = var.folder_id == null ? var.org_id : null

  labels = {
    team        = var.entry.project.team
    environment = var.entry.project.environment
    cost-center = replace(lower(var.entry.project.cost_center), "_", "-")
    managed-by  = "project-factory"
  }

  lifecycle {
    prevent_destroy = true
    # Project ID cannot change — detect and warn rather than recreate.
    ignore_changes = [org_id, folder_id]
  }
}

resource "google_billing_project_info" "billing" {
  project         = google_project.project.project_id
  billing_account = var.billing_account_id
}

# ── APIs ──────────────────────────────────────────────────────────────────────
# Base APIs every project gets regardless of registry entry.
# Additional APIs added per feature flag (gke.enabled, etc.)

locals {
  base_apis = [
    "compute.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "iam.googleapis.com",
    "logging.googleapis.com",
    "monitoring.googleapis.com",
    "billingbudgets.googleapis.com",
  ]

  gke_apis = try(var.entry.gke.enabled, false) ? [
    "container.googleapis.com",
    "artifactregistry.googleapis.com",
    "binaryauthorization.googleapis.com",
  ] : []

  all_apis = toset(concat(local.base_apis, local.gke_apis))
}

resource "google_project_service" "apis" {
  for_each = local.all_apis

  project            = google_project.project.project_id
  service            = each.value
  disable_on_destroy = false

  depends_on = [google_billing_project_info.billing]
}

output "project_id"     { value = google_project.project.project_id }
output "project_number" { value = google_project.project.number }
