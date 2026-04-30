# modules/vpc/outputs.tf

output "vpc_id" {
  description = "The unique identifier of the VPC network"
  value       = google_compute_network.vpc.id
}

output "vpc_name" {
  description = "The name of the VPC network"
  value       = google_compute_network.vpc.name
}

output "vpc_self_link" {
  description = "The URI of the VPC network — use this when referencing the VPC in other resources"
  value       = google_compute_network.vpc.self_link
}

output "vpc_gateway_ipv4" {
  description = "The default internet gateway IPv4 address for this VPC"
  value       = google_compute_network.vpc.gateway_ipv4
}

output "subnet_ids" {
  description = "Map of subnet name → subnet ID"
  value       = { for k, v in google_compute_subnetwork.subnets : k => v.id }
}

output "subnet_self_links" {
  description = "Map of subnet name → subnet self_link. Use self_link when attaching GKE clusters or VMs to subnets."
  value       = { for k, v in google_compute_subnetwork.subnets : k => v.self_link }
}

output "subnet_regions" {
  description = "Map of subnet name → region"
  value       = { for k, v in google_compute_subnetwork.subnets : k => v.region }
}

output "subnet_cidr_ranges" {
  description = "Map of subnet name → primary CIDR range"
  value       = { for k, v in google_compute_subnetwork.subnets : k => v.ip_cidr_range }
}

output "subnet_secondary_ranges" {
  description = "Map of subnet name → list of secondary ranges (name + CIDR)"
  value = {
    for k, v in google_compute_subnetwork.subnets : k => [
      for r in v.secondary_ip_range : {
        range_name    = r.range_name
        ip_cidr_range = r.ip_cidr_range
      }
    ]
  }
}

output "router_names" {
  description = "Map of region → Cloud Router name. Add BGP peers to these routers for VPN/Interconnect."
  value       = { for k, v in google_compute_router.routers : k => v.name }
}

output "nat_names" {
  description = "Map of region → Cloud NAT name"
  value       = { for k, v in google_compute_router_nat.nats : k => v.name }
}

output "firewall_rule_names" {
  description = "List of all firewall rule names created by this module"
  value = compact([
    var.enable_iap_ssh ? "${var.vpc_name}-allow-iap-ssh" : "",
    var.enable_http_https ? "${var.vpc_name}-allow-http-https" : "",
    length(var.internal_source_ranges) > 0 ? "${var.vpc_name}-allow-internal" : "",
    "${var.vpc_name}-allow-health-checks",
    var.enable_deny_all_ingress ? "${var.vpc_name}-deny-all-ingress" : "",
    "${var.vpc_name}-allow-all-egress",
  ])
}
