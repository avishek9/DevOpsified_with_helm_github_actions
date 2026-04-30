# modules/gke-service/main.tf
#
# GKE Standard regional cluster deployed in a SERVICE project,
# using a subnet from the HOST project's Shared VPC.
#
# Key differences from a non-Shared-VPC cluster:
#
#   network:    references the host project's VPC self_link (cross-project)
#   subnetwork: references the host project's subnet self_link (cross-project)
#   networking_mode: must be VPC_NATIVE for Shared VPC + private clusters
#
# The cluster's control plane is provisioned in the service project,
# but all data plane networking (nodes, pods, services) uses the
# host project's shared VPC.

terraform {
  required_version = ">= 1.5"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 5.0, < 6.0"
    }
  }
}

# ── GKE cluster ───────────────────────────────────────────────────────────────

resource "google_container_cluster" "cluster" {
  name        = var.cluster_name
  project     = var.service_project_id
  location    = var.region
  description = "GKE cluster in ${var.service_project_id} using shared VPC subnet from ${var.host_project_id}"

  remove_default_node_pool = true
  initial_node_count       = 1

  # ── Shared VPC networking ────────────────────────────────────────────────────
  # CRITICAL: use self_links not names here.
  # network and subnetwork reference resources in the HOST project.
  # If you use just the name (e.g. "shared-vpc"), GKE looks in the
  # service project — it won't find it and cluster creation fails with
  # a confusing "network not found" error.

  network    = var.shared_vpc_self_link   # host project VPC self_link
  subnetwork = var.subnet_self_link       # host project subnet self_link

  # VPC-native mode: required for Shared VPC + private clusters.
  # Uses alias IPs from the subnet's secondary ranges.
  networking_mode = "VPC_NATIVE"

  ip_allocation_policy {
    cluster_secondary_range_name  = var.pods_range_name
    services_secondary_range_name = var.services_range_name
  }

  # ── Private cluster ──────────────────────────────────────────────────────────
  # Nodes have no external IPs — all traffic stays on the shared VPC.
  # Control plane communicates with nodes via the master_ipv4_cidr_block
  # peered into the shared VPC's address space.

  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = var.enable_private_endpoint
    master_ipv4_cidr_block  = var.master_ipv4_cidr_block

    master_global_access_config {
      # true = control plane internal IP accessible from all regions.
      # Needed if CI/CD pipeline or kubectl users are outside the cluster region.
      enabled = true
    }
  }

  master_authorized_networks_config {
    dynamic "cidr_blocks" {
      for_each = var.master_authorized_networks
      content {
        cidr_block   = cidr_blocks.value.cidr_block
        display_name = cidr_blocks.value.display_name
      }
    }
    gcp_public_cidrs_access_enabled = false
  }

  # ── Dataplane V2 ─────────────────────────────────────────────────────────────
  datapath_provider = "ADVANCED_DATAPATH"

  # ── Workload Identity ─────────────────────────────────────────────────────────
  # Pods in the SERVICE project get tokens from the service project's
  # Workload Identity pool. The node SA is in the service project too.
  workload_identity_config {
    workload_pool = "${var.service_project_id}.svc.id.goog"
  }

  # ── Add-ons ───────────────────────────────────────────────────────────────────
  addons_config {
    http_load_balancing { disabled = false }
    horizontal_pod_autoscaling { disabled = false }
    network_policy_config { disabled = false }
  }

  network_policy {
    enabled  = true
    provider = "CALICO"
  }

  enable_intranode_visibility = true

  # ── Release channel & maintenance ─────────────────────────────────────────────
  release_channel {
    channel = var.release_channel
  }

  maintenance_policy {
    recurring_window {
      start_time = "2024-01-01T02:00:00Z"
      end_time   = "2024-01-01T06:00:00Z"
      recurrence = "FREQ=WEEKLY;BYDAY=SA,SU"
    }
  }

  # ── Logging & monitoring ──────────────────────────────────────────────────────
  logging_config {
    enable_components = [
      "SYSTEM_COMPONENTS",
      "WORKLOADS",
      "API_SERVER",
    ]
  }

  monitoring_config {
    enable_components = [
      "SYSTEM_COMPONENTS",
      "APISERVER",
      "POD",
      "DEPLOYMENT",
    ]
    managed_prometheus { enabled = true }
  }

  resource_labels = merge(
    {
      managed-by       = "terraform"
      host-project     = var.host_project_id
      service-project  = var.service_project_id
    },
    var.cluster_labels
  )

  lifecycle {
    prevent_destroy = false  # set true for production
    ignore_changes  = [node_config]
  }
}

# ── Node pool ─────────────────────────────────────────────────────────────────
# Single general-purpose pool for this lab.
# For production: add system pool (tainted) + spot pool.

resource "google_container_node_pool" "general" {
  name    = "${var.cluster_name}-general"
  project = var.service_project_id
  cluster = google_container_cluster.cluster.id

  autoscaling {
    min_node_count  = var.node_min_count
    max_node_count  = var.node_max_count
    location_policy = "BALANCED"
  }

  node_config {
    machine_type = var.node_machine_type
    spot         = false

    # Node SA from iam.tf in this module
    service_account = google_service_account.node_sa.email
    oauth_scopes    = ["https://www.googleapis.com/auth/cloud-platform"]

    # Nodes in Shared VPC: tag must match firewall rules in HOST project.
    # The host project firewall rules reference these tags.
    tags = ["gke-node", "allow-health-check"]

    labels = {
      pool            = "general"
      service-project = var.service_project_id
    }

    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }

    workload_metadata_config {
      mode = "GKE_METADATA"
    }

    metadata = {
      disable-legacy-endpoints = "true"
    }

    disk_size_gb = 100
    disk_type    = "pd-ssd"
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }

  upgrade_settings {
    max_surge       = 1
    max_unavailable = 0
    strategy        = "SURGE"
  }
}
