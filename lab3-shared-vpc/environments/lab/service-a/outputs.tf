# environments/lab/service-a/outputs.tf

output "cluster_name" {
  value = module.gke_a.cluster_name
}

output "get_credentials_command" {
  value = module.gke_a.get_credentials_command
}

output "workload_identity_pool" {
  value = module.gke_a.workload_identity_pool
}

output "node_service_account_email" {
  value = module.gke_a.node_service_account_email
}

output "verification_commands" {
  value = <<-EOT
    # 1. Get credentials
    ${module.gke_a.get_credentials_command}

    # 2. Confirm nodes have no external IPs
    kubectl get nodes -o wide

    # 3. Confirm cluster uses shared VPC subnet
    gcloud container clusters describe ${module.gke_a.cluster_name} \
      --region=${var.region} \
      --project=${var.service_project_id} \
      --format="yaml(networkConfig)"

    # 4. Confirm Workload Identity is enabled
    gcloud container clusters describe ${module.gke_a.cluster_name} \
      --region=${var.region} \
      --project=${var.service_project_id} \
      --format="yaml(workloadIdentityConfig)"

    # 5. Verify this service project cannot see service project B's subnet
    # The following should list ONLY subnet-service-a
    gcloud compute networks subnets list-usable \
      --project=${var.service_project_id}

    # 6. Confirm nodes registered in the cluster belong to subnet-service-a CIDRs
    kubectl get nodes -o jsonpath='{.items[*].status.addresses[?(@.type=="InternalIP")].address}'
    # All IPs should be in 10.10.0.0/20
  EOT
}
