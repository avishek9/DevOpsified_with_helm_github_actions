# modules/shared-vpc/main.tf
#
# Creates the host project network and wires Shared VPC.
#
# Dependency order inside this module:
#   1. VPC network
#   2. Subnets (reference VPC)
#   3. Shared VPC host enablement (references host project)
#   4. Service project attachment (references host enablement)
#   5. Subnet IAM bindings (references subnets + service project SA)
#   6. Cloud Router + NAT (references VPC)
#   7. Firewall rules (reference VPC)

terraform {
  required_version = ">= 1.5"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 5.0, < 6.0"
    }
  }
}

# ── VPC ───────────────────────────────────────────────────────────────────────

resource "google_compute_network" "shared_vpc" {
  name                    = var.vpc_name
  project                 = var.host_project_id
  auto_create_subnetworks = false
  routing_mode            = var.routing_mode
  description             = "Shared VPC — host project network. Managed by network team. Service projects attach via Shared VPC."
}

# ── Subnets ───────────────────────────────────────────────────────────────────
# One subnet per service project. Each subnet is scoped to one team.
# Secondary ranges are sized for GKE: /18 for pods, /22 for services.

resource "google_compute_subnetwork" "service_subnets" {
  for_each = var.service_projects

  name        = each.value.subnet_name
  project     = var.host_project_id
  network     = google_compute_network.shared_vpc.id
  region      = var.region
  description = each.value.description != "" ? each.value.description : "Subnet for service project ${each.key}"

  ip_cidr_range            = each.value.ip_cidr_range
  private_ip_google_access = true

  # Pods secondary range: GKE allocates a /24 per node from this pool.
  # /18 = 16382 IPs — enough for ~64 nodes at default pod density.
  secondary_ip_range {
    range_name    = "${each.value.subnet_name}-pods"
    ip_cidr_range = each.value.pods_cidr
  }

  # Services secondary range: GKE ClusterIP allocation pool.
  # /22 = 1022 IPs — sufficient for most clusters.
  secondary_ip_range {
    range_name    = "${each.value.subnet_name}-services"
    ip_cidr_range = each.value.services_cidr
  }

  log_config {
    aggregation_interval = "INTERVAL_5_SEC"
    flow_sampling        = 0.5
    metadata             = "INCLUDE_ALL_METADATA"
  }
}

# ── Enable Shared VPC on host project ─────────────────────────────────────────
# This designates the host project as a Shared VPC host.
# Must happen before any service project can be attached.
# Only one host enablement per project — idempotent on re-apply.

resource "google_compute_shared_vpc_host_project" "host" {
  project    = var.host_project_id
  depends_on = [google_compute_network.shared_vpc]
}

# ── Attach service projects to host ───────────────────────────────────────────
# Each service project must be explicitly attached.
# Attachment alone does not grant subnet access — that requires IAM below.
# A service project can only have ONE host project at a time.

resource "google_compute_shared_vpc_service_project" "attachments" {
  for_each = var.service_projects

  host_project    = var.host_project_id
  service_project = each.value.project_id

  # Must wait for host enablement to complete.
  depends_on = [google_compute_shared_vpc_host_project.host]
}

# ── Subnet IAM bindings ───────────────────────────────────────────────────────
# compute.networkUser on a SPECIFIC subnet grants the service project's
# workloads permission to attach resources (VMs, GKE nodes, LB backends)
# to that subnet only.
#
# Two principals need this binding for GKE to work:
#
#   1. The service project's GKE service account
#      (google-container-engine-robot@...) — GKE control plane uses this
#      to configure VPC routes and firewall rules during cluster creation.
#
#   2. The service project's Compute Engine default service account OR
#      the node service account — nodes use this for network attachment.
#
# IMPORTANT: granting compute.networkUser at the VPC level would give
# access to ALL subnets. Always grant at the subnet level for isolation.

# Binding 1: GKE service account in the service project
# This SA is auto-created when the container API is enabled.
# Format: service-PROJECT_NUMBER@container-engine-robot.iam.gserviceaccount.com
resource "google_compute_subnetwork_iam_member" "gke_sa_network_user" {
  for_each = var.service_projects

  project    = var.host_project_id
  region     = var.region
  subnetwork = google_compute_subnetwork.service_subnets[each.key].name
  role       = "roles/compute.networkUser"

  # The GKE service agent SA in the service project.
  # PROJECT_NUMBER is different from PROJECT_ID.
  # Use data source below to resolve project number.
  member = "serviceAccount:service-${data.google_project.service_projects[each.key].number}@container-engine-robot.iam.gserviceaccount.com"

  depends_on = [google_compute_shared_vpc_service_project.attachments]
}

# Binding 2: Google APIs service account in the service project
# Required for GKE to manage firewall rules and routes in the host VPC.
resource "google_compute_subnetwork_iam_member" "google_apis_network_user" {
  for_each = var.service_projects

  project    = var.host_project_id
  region     = var.region
  subnetwork = google_compute_subnetwork.service_subnets[each.key].name
  role       = "roles/compute.networkUser"

  member = "serviceAccount:${data.google_project.service_projects[each.key].number}@cloudservices.gserviceaccount.com"

  depends_on = [google_compute_shared_vpc_service_project.attachments]
}

# Binding 3: Host service agent role for GKE in the host project
# The GKE service agent in the SERVICE project needs this role in the
# HOST project to manage shared VPC resources (firewall rules, routes).
# Without this, cluster creation fails with "permission denied on host project".
resource "google_project_iam_member" "gke_host_service_agent" {
  for_each = var.service_projects

  project = var.host_project_id
  role    = "roles/container.hostServiceAgentUser"
  member  = "serviceAccount:service-${data.google_project.service_projects[each.key].number}@container-engine-robot.iam.gserviceaccount.com"

  depends_on = [google_compute_shared_vpc_service_project.attachments]
}

# Data source: resolve service project numbers from project IDs.
# Project number is required for service account email construction.
# It is NOT the same as the project ID (e.g. "my-project-123" vs 123456789).
data "google_project" "service_projects" {
  for_each   = var.service_projects
  project_id = each.value.project_id
}

# ── Cloud Router ───────────────────────────────────────────────────────────────
# One router for the region — hosts Cloud NAT for all subnets.
# If adding VPN or Interconnect later, attach tunnels to this router.

resource "google_compute_router" "router" {
  name    = "${var.vpc_name}-router-${var.region}"
  project = var.host_project_id
  network = google_compute_network.shared_vpc.id
  region  = var.region

  bgp {
    asn            = 64512
    advertise_mode = "DEFAULT"
  }
}

# ── Cloud NAT ─────────────────────────────────────────────────────────────────
# Private GKE nodes need internet egress for:
#   - OS package updates (apt/yum)
#   - Docker Hub image pulls (if not using Artifact Registry)
# Google API traffic uses Private Google Access — does NOT go through NAT.

resource "google_compute_router_nat" "nat" {
  count = var.create_nat ? 1 : 0

  name    = "${var.vpc_name}-nat-${var.region}"
  project = var.host_project_id
  router  = google_compute_router.router.name
  region  = var.region

  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"

  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}

# ── Firewall rules ─────────────────────────────────────────────────────────────
# Firewall rules live in the HOST project and apply to the shared VPC.
# Service project teams cannot create or modify these rules —
# all firewall changes go through the network team in the host project.
# This is both a security feature and a common operational friction point.

# IAP SSH: secure SSH without public port 22 exposure
resource "google_compute_firewall" "allow_iap_ssh" {
  count = var.enable_iap_ssh ? 1 : 0

  name        = "${var.vpc_name}-allow-iap-ssh"
  project     = var.host_project_id
  network     = google_compute_network.shared_vpc.id
  description = "Allow SSH from Google IAP. Tag VMs with allow-ssh to receive this rule."
  direction   = "INGRESS"
  priority    = 1000

  source_ranges = ["35.235.240.0/20"]
  target_tags   = ["allow-ssh"]

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  log_config { metadata = "INCLUDE_ALL_METADATA" }
}

# Internal traffic: VMs across all service project subnets can communicate.
# Covers all subnet primary CIDRs — secondary ranges (pods) route through GKE.
resource "google_compute_firewall" "allow_internal" {
  count = length(var.internal_ranges) > 0 ? 1 : 0

  name        = "${var.vpc_name}-allow-internal"
  project     = var.host_project_id
  network     = google_compute_network.shared_vpc.id
  description = "Allow all traffic between internal CIDRs. Tag VMs with allow-internal."
  direction   = "INGRESS"
  priority    = 2000

  source_ranges = var.internal_ranges
  target_tags   = ["allow-internal"]

  allow {
    protocol = "tcp"
    ports = ["0-65535"]
    }
  allow {
    protocol = "udp"
    ports = ["0-65535"]
    }
  allow { protocol = "icmp" }

  log_config { metadata = "INCLUDE_ALL_METADATA" }
}

# LB health checks: required for any GKE workload behind a GCP load balancer.
# Control plane → node traffic for kubelet and webhook ports.
resource "google_compute_firewall" "allow_health_checks" {
  name        = "${var.vpc_name}-allow-health-checks"
  project     = var.host_project_id
  network     = google_compute_network.shared_vpc.id
  description = "GCP LB health check ranges. Required for all load balancer backends."
  direction   = "INGRESS"
  priority    = 1000

  source_ranges = ["35.191.0.0/16", "130.211.0.0/22"]
  target_tags   = ["allow-health-check"]

  allow { protocol = "tcp" }

  log_config { metadata = "INCLUDE_ALL_METADATA" }
}

# GKE control plane → nodes: required for kubectl exec/logs/port-forward
# and for admission webhooks (Istio, OPA, etc.)
# Source range is the master_ipv4_cidr_block of each GKE cluster.
# This rule is intentionally broad — in production, scope per cluster CIDR.
resource "google_compute_firewall" "allow_master_to_nodes" {
  name        = "${var.vpc_name}-allow-master-to-nodes"
  project     = var.host_project_id
  network     = google_compute_network.shared_vpc.id
  description = "GKE control plane to node communication. Required for kubelet, webhooks, and kubectl exec."
  direction   = "INGRESS"
  priority    = 1000

  # RFC1918 private ranges — covers all possible control plane CIDRs.
  # Narrow to specific /28 blocks once clusters are created.
  source_ranges = ["172.16.0.0/12"]
  target_tags   = ["gke-node"]

  allow {
    protocol = "tcp"
    ports    = ["443", "8443", "9443", "10250", "15017"]
  }

  log_config { metadata = "INCLUDE_ALL_METADATA" }
}

# Deny all ingress — explicit, appears in audit logs
resource "google_compute_firewall" "deny_all_ingress" {
  name        = "${var.vpc_name}-deny-all-ingress"
  project     = var.host_project_id
  network     = google_compute_network.shared_vpc.id
  description = "Explicit deny-all ingress at priority 65534. Makes implicit deny visible in audit logs."
  direction   = "INGRESS"
  priority    = 65534

  source_ranges = ["0.0.0.0/0"]
  deny { protocol = "all" }

  log_config { metadata = "INCLUDE_ALL_METADATA" }
}
