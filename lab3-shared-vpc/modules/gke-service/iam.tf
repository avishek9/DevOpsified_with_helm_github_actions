# modules/gke-service/iam.tf
#
# Node service account for GKE nodes in the service project.
#
# In a Shared VPC setup, the node SA lives in the SERVICE project,
# not the host project. The IAM bindings for logging/monitoring
# are also in the service project — the node SA does not need
# permissions in the host project.
#
# The host project IAM (compute.networkUser, container.hostServiceAgentUser)
# was already granted by the shared-vpc module.

resource "google_service_account" "node_sa" {
  project      = var.service_project_id
  account_id   = "${var.cluster_name}-node-sa"
  display_name = "${var.cluster_name} node service account"
  description  = "Minimum-permission SA for GKE nodes in ${var.service_project_id}. Pods use Workload Identity."
}

resource "google_project_iam_member" "node_log_writer" {
  project = var.service_project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.node_sa.email}"
}

resource "google_project_iam_member" "node_metric_writer" {
  project = var.service_project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.node_sa.email}"
}

resource "google_project_iam_member" "node_monitoring_viewer" {
  project = var.service_project_id
  role    = "roles/monitoring.viewer"
  member  = "serviceAccount:${google_service_account.node_sa.email}"
}

resource "google_project_iam_member" "node_artifact_registry" {
  project = var.service_project_id
  role    = "roles/artifactregistry.reader"
  member  = "serviceAccount:${google_service_account.node_sa.email}"
}
