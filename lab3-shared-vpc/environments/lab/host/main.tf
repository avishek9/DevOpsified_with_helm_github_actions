# environments/lab/host/main.tf
#
# Apply this FIRST before service project environments.
# Creates: VPC, subnets, Shared VPC enablement, service project
# attachments, subnet IAM bindings, Cloud Router, NAT, firewall rules.

# Enable required APIs in host project
resource "google_project_service" "compute" {
  project            = var.host_project_id
  service            = "compute.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "container" {
  project            = var.host_project_id
  service            = "container.googleapis.com"
  disable_on_destroy = false
}

module "shared_vpc" {
  source = "../../../modules/shared-vpc"

  host_project_id = var.host_project_id
  vpc_name        = "shared-vpc"
  region          = var.region
  routing_mode    = "GLOBAL"

  # ── Service projects ────────────────────────────────────────────────────────
  # Each entry creates:
  #   - A subnet in the host project with secondary ranges
  #   - Shared VPC service project attachment
  #   - Subnet IAM bindings for GKE service agents
  service_projects = {
    "service-a" = {
      project_id    = var.service_project_a_id
      subnet_name   = "subnet-service-a"
      ip_cidr_range = "10.10.0.0/20"
      pods_cidr     = "10.100.0.0/18"
      services_cidr = "10.200.0.0/22"
      description   = "Subnet for service project A — team A workloads and GKE cluster"
    }
    "service-b" = {
      project_id    = var.service_project_b_id
      subnet_name   = "subnet-service-b"
      ip_cidr_range = "10.20.0.0/20"
      pods_cidr     = "10.104.0.0/18"
      services_cidr = "10.200.4.0/22"
      description   = "Subnet for service project B — team B workloads"
    }
  }

  # ── Firewall ─────────────────────────────────────────────────────────────────
  enable_iap_ssh = true

  # Internal ranges: all subnet primary CIDRs in the shared VPC.
  # VMs tagged allow-internal accept traffic from these ranges.
  internal_ranges = [
    "10.10.0.0/20",  # subnet-service-a
    "10.20.0.0/20",  # subnet-service-b
  ]

  create_nat = true

  depends_on = [
    google_project_service.compute,
    google_project_service.container,
  ]
}
