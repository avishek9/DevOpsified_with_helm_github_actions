# modules/networking/main.tf
#
# Per-project networking:
#   - Subnet in host project Shared VPC (always)
#   - Shared VPC service project attachment + IAM bindings (always)
#   - NCC spoke for on-prem connectivity (only if connect_to_onprem: true)
#
# The NCC spoke is the migration-specific piece. During migration,
# a team's project needs to reach on-prem systems (databases, APIs,
# Active Directory). The spoke connects this project's subnet to the
# NCC hub which has an Interconnect or VPN to on-prem.
# Once migration is complete: set connect_to_onprem: false, re-apply,
# and the spoke is cleanly removed.

terraform {
  required_providers {
    google = { source = "hashicorp/google"
    version = ">= 5.0, < 6.0" }
  }
}

variable "entry"           { type = any }
variable "host_project_id" { type = string }
variable "project_id"      { type = string }
variable "project_number"  { type = number }
variable "region"          { type = string }
variable "ncc_hub_id"      { type = string; default = null }

# ── Subnet in host project ────────────────────────────────────────────────────

resource "google_compute_subnetwork" "subnet" {
  # Subnet lives in HOST project, but is used by the SERVICE project.
  project = var.host_project_id
  name    = "subnet-${var.entry.project.team}-${var.entry.project.environment}"
  network = data.google_compute_network.shared_vpc.id
  region  = var.region

  ip_cidr_range            = var.entry.networking.subnet_cidr
  private_ip_google_access = true

  secondary_ip_range {
    range_name    = "pods-${var.entry.project.team}-${var.entry.project.environment}"
    ip_cidr_range = var.entry.networking.pods_cidr
  }

  secondary_ip_range {
    range_name    = "services-${var.entry.project.team}-${var.entry.project.environment}"
    ip_cidr_range = var.entry.networking.services_cidr
  }

  log_config {
    aggregation_interval = "INTERVAL_5_SEC"
    flow_sampling        = 0.5
    metadata             = "INCLUDE_ALL_METADATA"
  }
}

data "google_compute_network" "shared_vpc" {
  name    = "shared-vpc"
  project = var.host_project_id
}

# ── Shared VPC attachment ─────────────────────────────────────────────────────

resource "google_compute_shared_vpc_service_project" "attachment" {
  host_project    = var.host_project_id
  service_project = var.project_id
}

# Three IAM bindings required for GKE on Shared VPC (see lab3 explanation)
resource "google_compute_subnetwork_iam_member" "gke_robot" {
  project    = var.host_project_id
  region     = var.region
  subnetwork = google_compute_subnetwork.subnet.name
  role       = "roles/compute.networkUser"
  member     = "serviceAccount:service-${var.project_number}@container-engine-robot.iam.gserviceaccount.com"
  depends_on = [google_compute_shared_vpc_service_project.attachment]
}

resource "google_compute_subnetwork_iam_member" "google_apis" {
  project    = var.host_project_id
  region     = var.region
  subnetwork = google_compute_subnetwork.subnet.name
  role       = "roles/compute.networkUser"
  member     = "serviceAccount:${var.project_number}@cloudservices.gserviceaccount.com"
  depends_on = [google_compute_shared_vpc_service_project.attachment]
}

resource "google_project_iam_member" "host_service_agent" {
  project    = var.host_project_id
  role       = "roles/container.hostServiceAgentUser"
  member     = "serviceAccount:service-${var.project_number}@container-engine-robot.iam.gserviceaccount.com"
  depends_on = [google_compute_shared_vpc_service_project.attachment]
}

# ── NCC spoke — migration connectivity ───────────────────────────────────────
# Only created when connect_to_onprem: true in the registry entry.
# Connects this project's VPC as a spoke to the organisation's NCC hub.
# The hub has an Interconnect or VPN spoke to the on-prem datacenter.
# Result: workloads in this project can reach on-prem systems directly.
#
# Removal: set connect_to_onprem: false in the registry entry and re-apply.
# Terraform destroys the spoke cleanly. The hub and other spokes are unaffected.

resource "google_network_connectivity_spoke" "onprem" {
  # count drives conditional creation from the registry flag
  count = try(var.entry.networking.connect_to_onprem, false) ? 1 : 0

  name     = "spoke-${var.entry.project.team}-${var.entry.project.environment}"
  project  = var.host_project_id
  location = "global"
  hub      = var.ncc_hub_id

  description = <<-EOT
    Migration spoke for ${var.entry.project.team} ${var.entry.project.environment}.
    Provides on-prem connectivity during migration window.
    Remove connect_to_onprem flag post-cutover.
  EOT

  linked_vpc_network {
    uri                   = "projects/${var.project_id}/global/networks/default"
    exclude_export_ranges = []
  }
}

# ── Outputs ───────────────────────────────────────────────────────────────────

output "subnet_self_link" { value = google_compute_subnetwork.subnet.self_link }
output "subnet_name"      { value = google_compute_subnetwork.subnet.name }
output "pods_range_name" {
  value = "pods-${var.entry.project.team}-${var.entry.project.environment}"
}
output "services_range_name" {
  value = "services-${var.entry.project.team}-${var.entry.project.environment}"
}
output "ncc_spoke_id" {
  value = try(google_network_connectivity_spoke.onprem[0].id, null)
}
