# environments/lab/host/outputs.tf
#
# These outputs are read by service project environments via
# terraform_remote_state data source. All networking values
# that a service project needs come from here — the service
# project never directly references host project resources.

output "vpc_self_link" {
  description = "Shared VPC self_link — pass to GKE cluster's network field"
  value       = module.shared_vpc.vpc_self_link
}

output "subnet_self_links" {
  description = "Map of service project key → subnet self_link"
  value       = module.shared_vpc.subnet_self_links
}

output "pods_range_names" {
  description = "Map of service project key → pod range name"
  value       = module.shared_vpc.pods_range_names
}

output "services_range_names" {
  description = "Map of service project key → services range name"
  value       = module.shared_vpc.services_range_names
}

output "host_project_id" {
  description = "Host project ID"
  value       = module.shared_vpc.host_project_id
}

output "verification_commands" {
  description = "Verify Shared VPC setup after apply"
  value       = <<-EOT
    # 1. Confirm Shared VPC is enabled on host project
    gcloud compute shared-vpc organizations list-host-projects \
      --organization=YOUR_ORG_ID

    # 2. Confirm service projects are attached
    gcloud compute shared-vpc list-associated-resources ${var.host_project_id}

    # 3. List subnets visible to service project A
    # Should see ONLY subnet-service-a, not subnet-service-b
    gcloud compute networks subnets list-usable \
      --project=${var.service_project_a_id}

    # 4. List subnets visible to service project B
    # Should see ONLY subnet-service-b, not subnet-service-a
    gcloud compute networks subnets list-usable \
      --project=${var.service_project_b_id}

    # 5. Verify firewall rules exist in host project
    gcloud compute firewall-rules list \
      --project=${var.host_project_id} \
      --filter="network=shared-vpc" \
      --format="table(name,direction,priority,targetTags,sourceRanges)"
  EOT
}
