# modules/gke/outputs.tf

output "cluster_name" {
  description = "GKE cluster name"
  value       = google_container_cluster.primary.name
}

output "cluster_id" {
  description = "GKE cluster ID (projects/PROJECT/locations/REGION/clusters/NAME)"
  value       = google_container_cluster.primary.id
}

output "cluster_endpoint" {
  description = <<-EOT
    Private IP of the cluster API server.
    For private endpoint clusters, only reachable from within the VPC.
    Use with: gcloud container clusters get-credentials
  EOT
  value     = google_container_cluster.primary.endpoint
  sensitive = true
}

output "cluster_ca_certificate" {
  description = "Base64-encoded cluster CA certificate. Used by kubectl and CI/CD."
  value       = google_container_cluster.primary.master_auth[0].cluster_ca_certificate
  sensitive   = true
}

output "cluster_location" {
  description = "Cluster region (e.g. us-central1)"
  value       = google_container_cluster.primary.location
}

output "workload_identity_pool" {
  description = <<-EOT
    Workload Identity pool for this cluster.
    Format: PROJECT_ID.svc.id.goog
    Use in IAM bindings for Workload Identity:
      member = "serviceAccount:POOL[NAMESPACE/KSA_NAME]"
  EOT
  value = google_container_cluster.primary.workload_identity_config[0].workload_pool
}

output "node_service_account_email" {
  description = "Email of the GKE node service account"
  value       = google_service_account.node_sa.email
}

output "node_pool_names" {
  description = "Names of all node pools created"
  value = {
    system  = google_container_node_pool.system.name
    general = google_container_node_pool.general.name
    spot    = google_container_node_pool.spot.name
  }
}

output "get_credentials_command" {
  description = "Command to configure kubectl for this cluster"
  value       = "gcloud container clusters get-credentials ${google_container_cluster.primary.name} --region=${google_container_cluster.primary.location} --project=${var.project_id}"
}
