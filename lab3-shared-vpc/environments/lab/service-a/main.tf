# environments/lab/service-a/main.tf
#
# Deploys a GKE cluster in service project A using the shared VPC subnet.
# Reads networking values from the host project's Terraform state —
# the service project team never needs to know host project internals.
#
# Apply AFTER environments/lab/host has been applied successfully.

# Enable required APIs in service project
resource "google_project_service" "container" {
  project            = var.service_project_id
  service            = "container.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "compute" {
  project            = var.service_project_id
  service            = "compute.googleapis.com"
  disable_on_destroy = false
}

# ── Read host project outputs via remote state ────────────────────────────────
# This is the clean way to share values across Terraform workspaces.
# The service project environment reads what it needs from the host state —
# subnet self_links, range names, VPC self_link — without duplicating
# or hardcoding values that belong to the host project.
#
# Alternative: pass values as variables in tfvars (simpler but error-prone —
# a typo in a self_link causes a very confusing cluster creation failure).

data "terraform_remote_state" "host" {
  backend = "gcs"
  config = {
    bucket = var.state_bucket
    prefix = "lab3-shared-vpc/host"
  }
}

# ── GKE cluster using shared VPC subnet ──────────────────────────────────────

module "gke_a" {
  source = "../../../modules/gke-service"

  service_project_id = var.service_project_id
  host_project_id    = var.host_project_id
  cluster_name       = "cluster-service-a"
  region             = var.region

  # Networking values from host project state —
  # these reference resources that live in the host project.
  shared_vpc_self_link = data.terraform_remote_state.host.outputs.vpc_self_link
  subnet_self_link     = data.terraform_remote_state.host.outputs.subnet_self_links["service-a"]
  pods_range_name      = data.terraform_remote_state.host.outputs.pods_range_names["service-a"]
  services_range_name  = data.terraform_remote_state.host.outputs.services_range_names["service-a"]

  master_ipv4_cidr_block = var.master_ipv4_cidr_block
  enable_private_endpoint = true

  # Allow kubectl access from the service-a subnet.
  # With private endpoint, only IPs within the VPC can reach the API server.
  master_authorized_networks = [
    {
      cidr_block   = "10.10.0.0/20"
      display_name = "subnet-service-a — VMs here can reach API server"
    },
  ]

  release_channel    = "REGULAR"
  node_machine_type  = "e2-standard-4"
  node_min_count     = 1
  node_max_count     = 3

  cluster_labels = {
    team        = "team-a"
    cost-center = "team-a-budget"
  }

  depends_on = [
    google_project_service.container,
    google_project_service.compute,
  ]
}
