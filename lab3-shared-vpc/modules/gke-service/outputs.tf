# modules/gke-service/outputs.tf

output "cluster_name" {
  value = google_container_cluster.cluster.name
}

output "cluster_id" {
  value = google_container_cluster.cluster.id
}

output "cluster_endpoint" {
  value     = google_container_cluster.cluster.endpoint
  sensitive = true
}

output "node_service_account_email" {
  description = "Node SA email — used in Workload Identity bindings"
  value       = google_service_account.node_sa.email
}

output "workload_identity_pool" {
  description = "Workload Identity pool for this service project"
  value       = "${var.service_project_id}.svc.id.goog"
}

output "get_credentials_command" {
  description = "Configure kubectl for this cluster"
  value       = "gcloud container clusters get-credentials ${var.cluster_name} --region=${var.region} --project=${var.service_project_id}"
}
