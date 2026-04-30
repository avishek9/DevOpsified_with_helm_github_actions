# modules/vpc/main.tf
#
# Creates:
#   - Custom-mode VPC (no auto-subnets)
#   - Regional subnets with primary + secondary ranges
#   - Private Google Access enabled per subnet
#   - Cloud Router per region (prerequisite for NAT)
#   - Cloud NAT per region

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

resource "google_compute_network" "vpc" {
  name    = var.vpc_name
  project = var.project_id

  # CRITICAL: always use custom mode in production.
  # auto_create_subnetworks = true creates subnets in every region
  # using 10.128.0.0/9 which almost always overlaps with on-prem.
  auto_create_subnetworks = false

  routing_mode            = var.routing_mode
  description             = var.description

  # delete_default_routes_on_create removes the 0.0.0.0/0 default
  # internet route at creation time. Recommended when you want explicit
  # control over internet egress (e.g. all traffic via Cloud NAT only).
  # Set false if VMs need direct internet egress via external IPs.
  delete_default_routes_on_create = false
}

# ── Subnets ───────────────────────────────────────────────────────────────────

resource "google_compute_subnetwork" "subnets" {
  for_each = { for s in var.subnets : s.name => s }

  name        = each.value.name
  project     = var.project_id
  network     = google_compute_network.vpc.id
  region      = each.value.region
  description = each.value.description

  ip_cidr_range = each.value.ip_cidr_range

  # Private Google Access (PGA): allows VMs without external IPs to
  # reach Google APIs (Cloud Storage, BigQuery, Pub/Sub, etc.) using
  # internal routing — traffic never touches the public internet.
  # Must be enabled per-subnet. Forgetting this is the most common
  # reason private VMs silently fail to call Google APIs.
  private_ip_google_access = true

  # Secondary ranges: additional IP ranges on this subnet.
  # Required for GKE alias IPs (pods and services cannot share
  # the primary node IP range — they need dedicated secondary ranges).
  # Ranges must not overlap with:
  #   - The primary range of this subnet
  #   - Any other subnet in the VPC
  #   - Any peered or connected network ranges
  dynamic "secondary_ip_range" {
    for_each = each.value.secondary_ranges
    content {
      range_name    = secondary_ip_range.value.range_name
      ip_cidr_range = secondary_ip_range.value.ip_cidr_range
    }
  }

  # Enable VPC Flow Logs for network visibility and security analysis.
  # aggregation_interval: how often logs are aggregated (5 sec default).
  # flow_sampling:        fraction of flows logged (0.5 = 50%).
  # metadata:             INCLUDE_ALL_METADATA adds src/dst VM metadata.
  log_config {
    aggregation_interval = "INTERVAL_5_SEC"
    flow_sampling        = 0.5
    metadata             = "INCLUDE_ALL_METADATA"
  }
}

# ── Cloud Routers (one per region, prerequisite for NAT) ─────────────────────
# Cloud Router is also the BGP control plane if you later add VPN or
# Interconnect. Creating one now avoids recreating it later and losing
# BGP session history.

locals {
  # Derive unique regions from the subnet list
  regions = distinct([for s in var.subnets : s.region])
}

resource "google_compute_router" "routers" {
  for_each = var.create_nat ? toset(local.regions) : toset([])

  name    = "${var.vpc_name}-router-${each.value}"
  project = var.project_id
  network = google_compute_network.vpc.id
  region  = each.value

  bgp {
    # Private ASN range: 64512-65534.
    # Using a consistent formula (64512 + region index) for predictability.
    # In production, set this explicitly via a variable — never rely on
    # auto-assignment if you plan to add VPN or Interconnect later.
    asn            = 64512
    advertise_mode = "DEFAULT"
  }

  description = "Router for ${each.value} — NAT and future VPN/Interconnect"
}

# ── Cloud NAT (one per region) ────────────────────────────────────────────────
# Cloud NAT provides outbound internet for VMs without external IPs.
# It is NOT needed for Google API traffic if Private Google Access is on.
# It IS needed for: apt/yum updates, pulling from Docker Hub, etc.

resource "google_compute_router_nat" "nats" {
  for_each = var.create_nat ? toset(local.regions) : toset([])

  name    = "${var.vpc_name}-nat-${each.value}"
  project = var.project_id
  router  = google_compute_router.routers[each.value].name
  region  = each.value

  # AUTO_ONLY: GCP manages NAT IP allocation automatically.
  # MANUAL_ONLY: you specify static external IPs (use when on-prem
  # firewalls need to allowlist specific GCP egress IPs).
  nat_ip_allocate_option = "AUTO_ONLY"

  # ALL_SUBNETWORKS_ALL_IP_RANGES: NAT applies to all subnets in this
  # region including secondary ranges (GKE pod traffic).
  # Use LIST_OF_SUBNETWORKS to scope NAT to specific subnets only.
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"

  log_config {
    enable = true
    filter = var.nat_log_filter
  }

  # min_ports_per_vm: minimum NAT ports allocated per VM.
  # Default 64. Increase to 128-1024 for VMs making many connections
  # (e.g. crawlers, high-concurrency services) to avoid port exhaustion.
  min_ports_per_vm = 64

  # enable_endpoint_independent_mapping: RFC 4787 compliant NAT.
  # Required for some UDP protocols. Leave false unless needed.
  enable_endpoint_independent_mapping = false
}
