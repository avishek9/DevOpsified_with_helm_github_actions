# modules/projects/main.tf
#
# Creates GCP projects with billing linkage and API enablement.
#
# Why manage projects in Terraform:
#   - Reproducible: anyone can recreate the full environment from code
#   - Auditable: project creation is version-controlled and reviewable
#   - Consistent: labels, billing, and APIs are applied uniformly
#   - Safe: prevent_destroy guards against accidental project deletion
#
# Permission requirements for the Terraform SA running this:
#   - roles/resourcemanager.projectCreator  (at org or folder level)
#   - roles/billing.user                    (on the billing account)
#   - roles/resourcemanager.folderViewer    (if using folder_id)
#
# These are org-level permissions — the Terraform SA for project creation
# is typically a separate, more privileged SA than the one used for
# resource creation within projects.

terraform {
  required_version = ">= 1.5"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 5.0, < 6.0"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.0"
    }
  }
}

# ── Projects ──────────────────────────────────────────────────────────────────

resource "google_project" "projects" {
  for_each = var.projects

  # Project ID: globally unique, immutable after creation.
  # If a project with this ID was recently deleted, it enters a 30-day
  # soft-delete window — you cannot reuse the ID until it expires or
  # the deletion is confirmed. Plan IDs carefully.
  project_id = each.value.project_id

  name = each.value.name

  # Placement: folder takes precedence over org if both are set.
  # Personal GCP accounts: omit both and projects go under your account.
  folder_id = var.folder_id != null ? var.folder_id : null
  org_id    = var.folder_id == null && var.org_id != null ? var.org_id : null

  labels = merge(
    {
      managed-by = "terraform"
    },
    each.value.labels
  )

  lifecycle {
    # CRITICAL: prevent accidental project destruction.
    # A destroyed project takes everything with it — GKE clusters,
    # databases, storage buckets. Recovery requires a support ticket
    # and a 30-day window. Always set this on project resources.
    # To legitimately destroy: remove this block, re-apply, then destroy.
    prevent_destroy = true

    # Project IDs and org/folder placement cannot be changed after creation.
    # Ignore drift on these fields rather than failing or trying to recreate.
    ignore_changes = [org_id, folder_id]
  }
}

# ── Billing account linkage ───────────────────────────────────────────────────
# Billing must be linked before most APIs can be enabled.
# Without billing: compute, container, and other paid APIs fail to enable
# with a confusing "billing not enabled" error on the first resource creation.

resource "google_billing_project_info" "billing" {
  for_each = var.projects

  project         = google_project.projects[each.key].project_id
  billing_account = var.billing_account_id
}

# ── API enablement ────────────────────────────────────────────────────────────
# Enable APIs per project.
# Using a flat map keyed by "project_key/api" to iterate across
# all projects × all APIs in a single resource block.
#
# API enablement can take 30-60 seconds per API.
# On first apply for multiple projects this adds several minutes.
# Subsequent applies are fast (no-ops if already enabled).
#
# disable_on_destroy = false: do not disable APIs when Terraform destroys
# the resource. Disabling APIs destroys all resources using them in the
# project — almost never what you want when tearing down Terraform state.

locals {
  # Flatten: [{project_key, project_id, api}, ...]
  project_apis = flatten([
    for proj_key, proj in var.projects : [
      for api in proj.apis : {
        key        = "${proj_key}/${api}"
        project_id = proj.project_id
        api        = api
      }
    ]
  ])
}

resource "google_project_service" "apis" {
  for_each = {
    for entry in local.project_apis : entry.key => entry
  }

  project            = google_project.projects[split("/", each.key)[0]].project_id
  service            = each.value.api
  disable_on_destroy = false

  # APIs must wait for billing linkage — some APIs (compute, container)
  # fail to enable if billing is not yet attached.
  depends_on = [google_billing_project_info.billing]
}
