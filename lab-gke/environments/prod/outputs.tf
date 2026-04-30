# environments/prod/outputs.tf

output "cluster_name" {
  description = "Cluster name — use in gcloud and kubectl commands"
  value       = module.gke.cluster_name
}

output "cluster_location" {
  description = "Cluster region"
  value       = module.gke.cluster_location
}

output "get_credentials_command" {
  description = "Run this to configure kubectl"
  value       = module.gke.get_credentials_command
}

output "workload_identity_pool" {
  description = "Workload Identity pool — use in IAM member bindings"
  value       = module.gke.workload_identity_pool
}

output "node_service_account_email" {
  description = "GKE node SA email"
  value       = module.gke.node_service_account_email
}

output "node_pool_names" {
  description = "All node pool names"
  value       = module.gke.node_pool_names
}

output "my_service_gcp_sa_email" {
  description = "GCP SA email for my-service — annotate the Kubernetes SA with this"
  value       = google_service_account.my_service.email
}

output "kubernetes_sa_annotation" {
  description = "Paste this annotation into the my-service Kubernetes ServiceAccount"
  value       = "iam.gke.io/gcp-service-account: ${google_service_account.my_service.email}"
}

output "verification_commands" {
  description = "Post-apply verification commands"
  value       = <<-EOT
    # 1. Configure kubectl
    ${module.gke.get_credentials_command}

    # 2. Verify nodes — confirm no external IPs
    kubectl get nodes -o wide

    # 3. Verify node pools have correct taints
    kubectl get nodes -o json | jq '.items[].spec.taints'

    # 4. Verify Workload Identity is enabled
    gcloud container clusters describe ${module.gke.cluster_name} \
      --region=${module.gke.cluster_location} \
      --project=${var.project_id} \
      --format="yaml(workloadIdentityConfig)"

    # 5. Verify Binary Authorization is enforcing
    gcloud container clusters describe ${module.gke.cluster_name} \
      --region=${module.gke.cluster_location} \
      --project=${var.project_id} \
      --format="yaml(binaryAuthorization)"

    # 6. Verify private cluster config
    gcloud container clusters describe ${module.gke.cluster_name} \
      --region=${module.gke.cluster_location} \
      --project=${var.project_id} \
      --format="yaml(privateClusterConfig)"

    # 7. Verify shielded nodes on all pools
    gcloud container node-pools list \
      --cluster=${module.gke.cluster_name} \
      --region=${module.gke.cluster_location} \
      --project=${var.project_id} \
      --format="table(name,config.shieldedInstanceConfig.enableSecureBoot)"

    # 8. Test Workload Identity — deploy a pod and verify it gets a token
    kubectl run wi-test --image=google/cloud-sdk:slim \
      --serviceaccount=my-service-ksa \
      --namespace=production \
      --rm -it --restart=Never \
      -- gcloud auth print-access-token
    # Should print a token, not "permission denied"
  EOT
}
