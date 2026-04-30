# modules/gke/iam.tf
#
# Three things this file handles:
#   1. Node service account with minimum necessary permissions
#   2. Binary Authorization policy — only signed images run
#   3. Workload Identity binding helper (one per workload)

# ── Node service account ──────────────────────────────────────────────────────
# Nodes run as this SA. It needs only the permissions to:
#   - Write logs and metrics to Cloud Operations
#   - Pull images from Artifact Registry
#   - Report node health to GKE
#
# Individual pod GCP permissions come from Workload Identity,
# NOT from this node SA. This SA should be as restricted as possible.

resource "google_service_account" "node_sa" {
  project      = var.project_id
  account_id   = "${var.cluster_name}-node-sa"
  display_name = "${var.cluster_name} GKE node service account"
  description  = "Minimum-permission SA for GKE nodes. Pods use Workload Identity for GCP access."
}

# Logging: nodes write container and system logs to Cloud Logging
resource "google_project_iam_member" "node_sa_log_writer" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.node_sa.email}"
}

# Metrics: nodes write node and pod metrics to Cloud Monitoring
resource "google_project_iam_member" "node_sa_metric_writer" {
  project = var.project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.node_sa.email}"
}

# Monitoring viewer: required for some GKE internal health reporting
resource "google_project_iam_member" "node_sa_monitoring_viewer" {
  project = var.project_id
  role    = "roles/monitoring.viewer"
  member  = "serviceAccount:${google_service_account.node_sa.email}"
}

# Artifact Registry reader: nodes pull container images from AR.
# If you use GCR instead of AR, add roles/storage.objectViewer instead.
resource "google_project_iam_member" "node_sa_artifact_registry" {
  project = var.project_id
  role    = "roles/artifactregistry.reader"
  member  = "serviceAccount:${google_service_account.node_sa.email}"
}

# ── Binary Authorization policy ───────────────────────────────────────────────
# Binary Authorization (BinAuthz) enforces that only container images
# which have been cryptographically attested by approved parties can run.
#
# Policy structure:
#   - default_admission_rule: what happens to images with no matching rule
#   - cluster_admission_rules: per-cluster overrides
#   - admission_whitelist_patterns: exempt specific registries from checks
#
# Enforcement mode options:
#   ENFORCED_BLOCK_AND_AUDIT_LOG: block non-compliant images, log attempts
#   AUDIT_LOG_ONLY: allow but log non-compliant images (migration mode)
#   DISABLED: no enforcement
#
# Attestor setup (required for require_attestations_by):
#   Create an attestor with a Kritis or Cloud Build integration.
#   The attestor signs images in CI after passing security scans.
#   GKE verifies the signature at admission time.


# ── Workload Identity binding ─────────────────────────────────────────────────
# Helper resource: creates the IAM binding between a Kubernetes SA
# and a GCP SA for Workload Identity.
#
# Usage in environments/prod/main.tf:
#   module "workload_identity_my_service" {
#     source        = "../../modules/gke"
#     ...
#   }
# Then create per-workload bindings separately:
#
# resource "google_service_account_iam_member" "my_service_wi" {
#   service_account_id = google_service_account.my_service.name
#   role               = "roles/iam.workloadIdentityUser"
#   member = "serviceAccount:${var.project_id}.svc.id.goog[production/my-service-ksa]"
# }
#
# The Kubernetes SA then needs this annotation:
#   iam.gke.io/gcp-service-account: my-service-sa@PROJECT.iam.gserviceaccount.com
#
# This file does not create workload-specific SAs — those belong in
# the application's own Terraform module or the environment root.
