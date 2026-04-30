# environments/dev/outputs.tf
#
# Expose useful values for post-apply verification and for
# downstream Terraform configurations (e.g. GKE cluster module
# that needs subnet self_links and secondary range names).

output "vpc_name" {
  description = "VPC name — use in gcloud commands: --filter=network=VALUE"
  value       = module.vpc.vpc_name
}

output "vpc_id" {
  description = "VPC ID"
  value       = module.vpc.vpc_id
}

output "subnets" {
  description = "All subnet details — self_link, CIDR, secondary ranges"
  value = {
    for name, self_link in module.vpc.subnet_self_links : name => {
      self_link       = self_link
      ip_cidr_range   = module.vpc.subnet_cidr_ranges[name]
      secondary_ranges = module.vpc.subnet_secondary_ranges[name]
      region          = module.vpc.subnet_regions[name]
    }
  }
}

output "gke_subnet_config" {
  description = <<-EOT
    Ready-to-use GKE subnet configuration.
    Paste these values into your GKE cluster Terraform module:
      subnetwork             = subnets["subnet-us-central1-dev"].self_link
      cluster_secondary_range_name  = "subnet-us-central1-dev-pods"
      services_secondary_range_name = "subnet-us-central1-dev-services"
  EOT
  value = {
    for name, self_link in module.vpc.subnet_self_links : name => {
      subnetwork                    = self_link
      cluster_secondary_range_name  = "${name}-pods"
      services_secondary_range_name = "${name}-services"
    }
  }
}

output "cloud_routers" {
  description = "Cloud Router names per region — add VPN/Interconnect peers to these"
  value       = module.vpc.router_names
}

output "firewall_rules" {
  description = "All firewall rule names created"
  value       = module.vpc.firewall_rule_names
}

output "verification_commands" {
  description = "Copy-paste commands to verify the deployment"
  value       = <<-EOT
    # 1. List subnets and confirm Private Google Access is enabled
    gcloud compute networks subnets list \
      --filter="network=${module.vpc.vpc_name}" \
      --format="table(name,region,ipCidrRange,privateIpGoogleAccess)"

    # 2. List secondary ranges
    gcloud compute networks subnets list \
      --filter="network=${module.vpc.vpc_name}" \
      --format="yaml(name,secondaryIpRanges)"

    # 3. List firewall rules
    gcloud compute firewall-rules list \
      --filter="network=${module.vpc.vpc_name}" \
      --format="table(name,direction,priority,sourceRanges,targetTags,denied[].protocol,allowed[].protocol)"

    # 4. Confirm VPC is custom mode (autoCreateSubnetworks = false)
    gcloud compute networks describe ${module.vpc.vpc_name} \
      --format="yaml(autoCreateSubnetworks,routingConfig,subnetworks)"

    # 5. List Cloud NAT instances
    gcloud compute routers list \
      --filter="network=${module.vpc.vpc_name}" \
      --format="table(name,region)"
  EOT
}
