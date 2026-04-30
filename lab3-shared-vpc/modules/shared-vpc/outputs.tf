# modules/shared-vpc/outputs.tf

output "vpc_id" {
  description = "Shared VPC network ID"
  value       = google_compute_network.shared_vpc.id
}

output "vpc_name" {
  description = "Shared VPC network name"
  value       = google_compute_network.shared_vpc.name
}

output "vpc_self_link" {
  description = "Shared VPC self_link — use when attaching GKE clusters"
  value       = google_compute_network.shared_vpc.self_link
}

output "subnet_self_links" {
  description = <<-EOT
    Map of service project key → subnet self_link.
    Pass subnet self_link to GKE cluster's subnetwork field.
    Using self_link (not name) avoids ambiguity across projects.
  EOT
  value = {
    for k, v in google_compute_subnetwork.service_subnets : k => v.self_link
  }
}

output "subnet_names" {
  description = "Map of service project key → subnet name"
  value = {
    for k, v in google_compute_subnetwork.service_subnets : k => v.name
  }
}

output "pods_range_names" {
  description = "Map of service project key → pod secondary range name"
  value = {
    for k, v in var.service_projects : k => "${v.subnet_name}-pods"
  }
}

output "services_range_names" {
  description = "Map of service project key → services secondary range name"
  value = {
    for k, v in var.service_projects : k => "${v.subnet_name}-services"
  }
}

output "host_project_id" {
  description = "Host project ID — needed by GKE cluster configuration"
  value       = var.host_project_id
}

output "router_name" {
  description = "Cloud Router name — attach VPN/Interconnect tunnels here"
  value       = google_compute_router.router.name
}

output "service_project_numbers" {
  description = "Map of service project key → project number"
  value = {
    for k, v in data.google_project.service_projects : k => v.number
  }
}
