# modules/iam/main.tf
#
# Applies IAM bindings from the registry entry to the service project.
# Teams declare their own members — platform team approves via PR review.
# No IAM changes happen without a registry PR + pipeline run.
#
# This is the governance model: teams self-declare who gets access,
# platform team reviews for policy violations (e.g. external accounts,
# overly broad roles), pipeline applies on merge.

terraform {
  required_providers {
    google = { source = "hashicorp/google"
    version = ">= 5.0, < 6.0" }
  }
}

variable "entry"      { type = any }
variable "project_id" { type = string }

# ── Flatten IAM members from registry ────────────────────────────────────────
# Registry structure:
#   iam:
#     owners:  [...]
#     editors: [...]
#     viewers: [...]
#
# Flattened to: [{role, member}, ...] for for_each

locals {
  iam_bindings = flatten([
    for role_key, members in {
      owners  = "roles/owner"
      editors = "roles/editor"
      viewers = "roles/viewer"
    } : [
      for member in try(var.entry.iam[role_key], []) : {
        # Unique key per binding — role + member
        key    = "${role_key}/${member}"
        role   = members
        member = member
      }
    ]
  ])
}

resource "google_project_iam_member" "team_bindings" {
  for_each = { for b in local.iam_bindings : b.key => b }

  project = var.project_id
  role    = each.value.role
  member  = each.value.member
}

# ── Default node SA for GKE ───────────────────────────────────────────────────
# Every project with GKE enabled gets a dedicated node SA.
# Individual pods use Workload Identity — the node SA has minimum permissions.

resource "google_service_account" "node_sa" {
  count = try(var.entry.gke.enabled, false) ? 1 : 0

  project      = var.project_id
  account_id   = "gke-node-sa"
  display_name = "GKE node SA — ${var.entry.project.team} ${var.entry.project.environment}"
  description  = "Minimum-permission node SA. Pods use Workload Identity."
}

resource "google_project_iam_member" "node_log_writer" {
  count   = try(var.entry.gke.enabled, false) ? 1 : 0
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.node_sa[0].email}"
}

resource "google_project_iam_member" "node_metric_writer" {
  count   = try(var.entry.gke.enabled, false) ? 1 : 0
  project = var.project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.node_sa[0].email}"
}

resource "google_project_iam_member" "node_ar_reader" {
  count   = try(var.entry.gke.enabled, false) ? 1 : 0
  project = var.project_id
  role    = "roles/artifactregistry.reader"
  member  = "serviceAccount:${google_service_account.node_sa[0].email}"
}

output "node_sa_email" {
  value = try(google_service_account.node_sa[0].email, null)
}
