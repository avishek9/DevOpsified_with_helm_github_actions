# environments/prod/main.tf
#
# Production GKE cluster environment root.
# Calls the GKE module and wires in networking from the lab1-vpc module.
#
# Prerequisites:
#   1. lab1-vpc has been applied — VPC and subnets exist
#   2. APIs enabled: container.googleapis.com, binaryauthorization.googleapis.com
#   3. State bucket exists for remote state

# ── Enable required APIs ──────────────────────────────────────────────────────
# Some teams manage API enablement separately. Included here for completeness.

resource "google_project_service" "container" {
  project            = var.project_id
  service            = "container.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "binaryauthorization" {
  project            = var.project_id
  service            = "binaryauthorization.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "artifactregistry" {
  project            = var.project_id
  service            = "artifactregistry.googleapis.com"
  disable_on_destroy = false
}

# ── GKE cluster ───────────────────────────────────────────────────────────────

module "gke" {
  source = "../../modules/gke"

  project_id   = var.project_id
  region       = var.region
  cluster_name = "prod-cluster"
  description  = "Production GKE Standard cluster — regional, private, Workload Identity"

  # ── Networking ──────────────────────────────────────────────────────────────
  # These reference outputs from the lab1-vpc module.
  # If managing in the same workspace, use module.vpc.outputs directly.
  # If separate workspaces, use data sources or remote state references.

  network    = var.vpc_name
  subnetwork = var.subnet_name

  # Secondary ranges created in lab1-vpc module:
  pods_range_name     = var.pods_range_name
  services_range_name = var.services_range_name

  # Control plane CIDR — /28 required, cannot change after creation.
  # Must not overlap with any subnet, secondary range, or peered network.
  master_ipv4_cidr_block = var.master_ipv4_cidr_block

  # Private endpoint: API server only reachable via internal VPC IP.
  # Set false initially if your CI/CD has no VPC access yet,
  # then migrate to true once bastion/IAP access is configured.
  enable_private_endpoint = true

  # Authorised networks for the API server.
  # With private endpoint = true, these are internal CIDRs.
  # Include your bastion VM's subnet or Cloud Shell's VPC range.
  master_authorized_networks = [
    {
      cidr_block   = "10.10.0.0/20"  # us-central1 subnet (from lab1-vpc)
      display_name = "us-central1 subnet — VMs in this subnet can reach API server"
    },
    # Add on-prem CIDR if connected via VPN/Interconnect:
    # {
    #   cidr_block   = "192.168.0.0/16"
    #   display_name = "on-prem network"
    # },
  ]

  # ── Release & maintenance ────────────────────────────────────────────────

  release_channel = "REGULAR"

  # Maintenance window: Saturdays and Sundays 02:00–06:00 UTC.
  # Adjust for your workload timezone — 02:00 UTC = 21:00 EST,
  # which may be business hours in some regions.
  maintenance_start_time = "2024-01-01T02:00:00Z"
  maintenance_end_time   = "2024-01-01T06:00:00Z"
  maintenance_recurrence = "FREQ=WEEKLY;BYDAY=SA,SU"

  # ── Node pools ───────────────────────────────────────────────────────────

  # Node SA email — created by the module, referenced back here.
  # On first apply: comment this out and use the module's output.
  # On subsequent applies: module creates the SA, this reference resolves.
  # Alternatively use a data source for an externally created SA.
  node_service_account_email = module.gke.node_service_account_email

  system_pool_machine_type  = "e2-standard-4"
  system_pool_node_count    = 1  # per zone → 3 total in regional cluster

  general_pool_machine_type = "n2-standard-8"
  general_pool_min_nodes    = 1  # per zone
  general_pool_max_nodes    = 10 # per zone

  spot_pool_machine_type = "n2-standard-8"
  spot_pool_max_nodes    = 5  # per zone

  node_disk_size_gb = 100
  node_disk_type    = "pd-ssd"

  # Network tags on nodes — must match firewall rules from lab1-vpc module.
  node_tags = ["allow-health-check", "gke-prod-node"]

  # ── Security ─────────────────────────────────────────────────────────────

  # Binary Authorization: enforce image signing.
  # Start with DISABLED if attestors are not yet configured,
  # then switch to PROJECT_SINGLETON_POLICY_ENFORCE once CI signing is set up.
  binary_authorization_mode = "PROJECT_SINGLETON_POLICY_ENFORCE"

  # ── Labels ───────────────────────────────────────────────────────────────

  cluster_labels = {
    team        = "platform"
    cost-center = "infra"
    criticality = "high"
  }

  depends_on = [
    google_project_service.container,
    google_project_service.binaryauthorization,
    google_project_service.artifactregistry,
  ]
}

# ── Workload Identity bindings ────────────────────────────────────────────────
# One block per application workload that needs GCP API access.
# Pattern: GCP SA → IAM binding → annotated Kubernetes SA → pod.

# Example: my-service in the production namespace
resource "google_service_account" "my_service" {
  project      = var.project_id
  account_id   = "my-service-prod-sa"
  display_name = "my-service production workload identity SA"
  description  = "GCP SA for my-service in production namespace. Access via Workload Identity only."
}

# Grant the GCP SA permission to be impersonated by the Kubernetes SA.
# The Kubernetes SA (my-service-ksa) must exist in the production namespace.
# Create it via Helm chart or separately applied manifest.
resource "google_service_account_iam_member" "my_service_workload_identity" {
  service_account_id = google_service_account.my_service.name
  role               = "roles/iam.workloadIdentityUser"

  # Format: serviceAccount:WORKLOAD_POOL[NAMESPACE/KSA_NAME]
  member = "serviceAccount:${module.gke.workload_identity_pool}[production/my-service-ksa]"
}


# ── Firewall rule for GKE nodes ───────────────────────────────────────────────
# GKE requires specific firewall rules that lab1-vpc may not include.
# This rule allows the control plane to reach nodes for webhooks and metrics.

resource "google_compute_firewall" "gke_master_to_nodes" {
  name        = "prod-cluster-master-to-nodes"
  project     = var.project_id
  network     = var.vpc_name
  description = "Allow GKE control plane to reach nodes on webhook and metrics ports."
  direction   = "INGRESS"
  priority    = 1000

  # GKE control plane source range is derived from master_ipv4_cidr_block.
  # The control plane VMs are in this /28 range.
  source_ranges = [var.master_ipv4_cidr_block]

  target_tags = ["gke-prod-node"]

  allow {
    protocol = "tcp"
    ports = [
      "443",   # Webhook servers (Istio, OPA, custom admission webhooks)
      "8443",  # Alternative webhook port
      "9443",  # Istio webhook
      "10250", # kubelet metrics — required for kubectl exec/logs/port-forward
      "15017", # Istio control plane webhook
    ]
  }
}
