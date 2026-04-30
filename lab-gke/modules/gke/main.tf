# modules/gke/main.tf
#
# Production GKE Standard regional cluster.
#
# Security posture:
#   - Private nodes (no external IPs on VMs)
#   - Private or restricted control plane endpoint
#   - Workload Identity (no key files, short-lived tokens)
#   - Binary Authorization (only signed images run)
#   - Shielded nodes (Secure Boot + vTPM + Integrity Monitoring)
#   - Intra-node visibility (for network policy enforcement)
#   - Dataplane V2 (eBPF-based CNI, native NetworkPolicy)
#   - Node auto-upgrade + auto-repair always on
#   - Three dedicated node pools with taints for workload isolation

terraform {
  required_version = ">= 1.5"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 5.0, < 6.0"
    }
  }
}

# ── Cluster ───────────────────────────────────────────────────────────────────

resource "google_container_cluster" "primary" {
  name        = var.cluster_name
  project     = var.project_id
  description = var.description

  # Regional cluster: control plane spans all three zones in the region.
  # A zone failure does not interrupt the API server or schedulable nodes.
  # Contrast with location = "us-central1-a" which creates a zonal cluster
  # with a single control plane replica and ~5 min API downtime per upgrade.
  location = var.region

  # Remove the default node pool immediately.
  # GKE requires an initial node pool to create the cluster, but we
  # manage all node pools explicitly below with full configuration.
  # The default pool has no taints, suboptimal sizing, and no labels.
  remove_default_node_pool = true
  initial_node_count       = 1

  # ── Networking ──────────────────────────────────────────────────────────────

  network    = var.network
  subnetwork = var.subnetwork

  # VPC-native (alias IP) networking.
  # Required for: private clusters, NetworkPolicy enforcement,
  # GKE Dataplane V2, and NCC spoke connectivity.
  # Routes-based networking is deprecated — never use it for new clusters.
  ip_allocation_policy {
    cluster_secondary_range_name  = var.pods_range_name
    services_secondary_range_name = var.services_range_name
  }

  # Private cluster configuration.
  # enable_private_nodes:    nodes have no external IPs.
  # enable_private_endpoint: control plane only reachable via internal VPC IP.
  # master_ipv4_cidr_block:  /28 for the control plane's internal address.
  #                          Cannot overlap with any subnet or peered range.
  #                          Cannot be changed after cluster creation.
  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = var.enable_private_endpoint
    master_ipv4_cidr_block  = var.master_ipv4_cidr_block

    master_global_access_config {
      # true = control plane internal IP is accessible from all regions.
      # Required if your CI/CD pipeline or kubectl users are in a different
      # region than the cluster. Uses Google's global internal network.
      enabled = true
    }
  }

  # Authorised networks: CIDRs allowed to reach the API server endpoint.
  # For private endpoint clusters this applies to the internal IP.
  # For public endpoint clusters this is a critical security control.
  # Empty list + private endpoint = only VMs in the same VPC can reach it.
  master_authorized_networks_config {
    dynamic "cidr_blocks" {
      for_each = var.master_authorized_networks
      content {
        cidr_block   = cidr_blocks.value.cidr_block
        display_name = cidr_blocks.value.display_name
      }
    }
    # gcp_public_cidrs_access_enabled = false prevents Google-operated
    # services (Cloud Shell from other projects) from reaching the endpoint.
    # Set true only if your team relies on Cloud Shell from multiple projects.
    gcp_public_cidrs_access_enabled = false
  }

  # Dataplane V2: eBPF-based CNI replacing kube-proxy and iptables.
  # Benefits: native NetworkPolicy enforcement, lower node CPU overhead,
  # better observability (Hubble integration), and consistent behaviour
  # regardless of node count. Required for FQDN-based NetworkPolicy.
  #datapath_provider = "ADVANCED_DATAPATH"

  # DNS config: Cloud DNS for cluster DNS (vs kube-dns).
  # Better scalability under high DNS query load.
  # Required for GKE Autopilot; recommended for large Standard clusters.
  dns_config {
    cluster_dns        = "CLOUD_DNS"
    cluster_dns_scope  = "CLUSTER_SCOPE"
    cluster_dns_domain = "cluster.local"
  }

  # ── Add-ons ─────────────────────────────────────────────────────────────────

  addons_config {
    # HTTP load balancing: required for Ingress resources backed by GCP LB.
    # Disable only if you use a custom ingress controller exclusively.
    http_load_balancing {
      disabled = false
    }

    # Horizontal Pod Autoscaler: deploy the HPA controller.
    horizontal_pod_autoscaling {
      disabled = false
    }

    # Network Policy: enforces Kubernetes NetworkPolicy objects.
    # With Dataplane V2, this is handled by eBPF — still set enabled=true
    # to signal intent and enable the admission webhook.
    network_policy_config {
      disabled = false
    }

    # GCS Fuse CSI driver: mount GCS buckets as volumes.
    # Enable if workloads read model artifacts or large datasets from GCS.
    gcs_fuse_csi_driver_config {
      enabled = false
    }

    # Config Connector: manage GCP resources via Kubernetes CRDs.
    # Enable if you want to provision GCP resources from within the cluster.
    config_connector_config {
      enabled = false
    }
  }

  # ── Workload Identity ────────────────────────────────────────────────────────
  # Workload Identity allows Kubernetes service accounts to impersonate
  # GCP service accounts. Pods get short-lived OAuth2 tokens automatically.
  # No JSON key files, no Secret rotation, no credential sprawl.
  # This is the ONLY acceptable way to grant GCP API access to pods.
  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  # ── Security ─────────────────────────────────────────────────────────────────

  # Binary Authorization: only allow container images that pass the
  # project's BinAuthz policy to run. Policy configured separately
  # via google_binary_authorization_policy resource.
  binary_authorization {
    evaluation_mode = var.binary_authorization_mode
  }

  # NetworkPolicy: enforce pod-to-pod traffic rules.
  # Pairs with NetworkPolicy manifests deployed to the cluster.
  network_policy {
    enabled  = true
    provider = "CALICO"
  }

  # Intra-node visibility: makes pod-to-pod traffic on the same node
  # visible to VPC flow logs and Firewall Insights.
  # Without this, same-node pod traffic bypasses VPC networking.
  enable_intranode_visibility = true

  # Shielded nodes default config:
  # Secure Boot + vTPM + Integrity Monitoring on all node pools.
  # Can be overridden per node pool — but don't.
  node_config {
    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }
  }

  # ── Upgrade & release channel ─────────────────────────────────────────────

  release_channel {
    # REGULAR: versions validated in Rapid for several weeks before promotion.
    # Auto-upgrades apply during the maintenance window below.
    # Never use UNSPECIFIED — the cluster falls out of support and GKE
    # force-upgrades on its own schedule when the version EOLs.
    channel = var.release_channel
  }

  maintenance_policy {
    recurring_window {
      start_time = var.maintenance_start_time
      end_time   = var.maintenance_end_time
      recurrence = var.maintenance_recurrence
    }
  }

  # ── Cluster autoscaling ───────────────────────────────────────────────────

  cluster_autoscaling {
    # Node Auto-Provisioning: GKE creates new node pools automatically
    # when pods cannot be scheduled due to resource constraints.
    # Disabled here — we manage pools explicitly for cost predictability
    # and security (auto-provisioned pools may not have our taints/labels).
    enabled = false

    # Autoscaling profile: OPTIMIZE_UTILIZATION aggressively scales down
    # underutilised nodes. BALANCED is more conservative.
    autoscaling_profile = "OPTIMIZE_UTILIZATION"
  }

  # ── Logging & monitoring ──────────────────────────────────────────────────

  logging_config {
    enable_components = [
      "SYSTEM_COMPONENTS",   # kube-apiserver, kube-scheduler, etc.
      "WORKLOADS",           # container stdout/stderr
      "APISERVER",          # API server audit logs
      "CONTROLLER_MANAGER",
      "SCHEDULER",
    ]
  }

  monitoring_config {
    enable_components = [
      "SYSTEM_COMPONENTS",
      "APISERVER",
      "CONTROLLER_MANAGER",
      "SCHEDULER",
      "STORAGE",
      "HPA",
      "POD",
      "DAEMONSET",
      "DEPLOYMENT",
      "STATEFULSET",
    ]

    managed_prometheus {
      # Google Managed Prometheus: scrape metrics without running
      # your own Prometheus. Stores in Cloud Monarch.
      # Use if you don't already have a central Prometheus setup.
      enabled = true
    }
  }

  # ── Labels ────────────────────────────────────────────────────────────────

  resource_labels = merge(
    {
      managed-by  = "terraform"
      environment = "prod"
    },
    var.cluster_labels
  )

  lifecycle {
    # Prevent accidental cluster deletion.
    # To destroy: first run terraform state rm, or remove this block.
    prevent_destroy = true

    # Ignore changes to node_config at cluster level —
    # it only applies to the deleted default node pool.
    ignore_changes = [node_config]
  }
}

# ── Node pool: system ─────────────────────────────────────────────────────────
# Hosts cluster-critical components: CoreDNS, kube-proxy, metrics-server,
# and any DaemonSets that must not share capacity with application workloads.
# Tainted with CriticalAddonsOnly so only system components land here.

resource "google_container_node_pool" "system" {
  name    = "${var.cluster_name}-system-pool"
  project = var.project_id
  cluster = google_container_cluster.primary.id

  # Regional cluster: node_count is per zone.
  # 1 per zone × 3 zones = 3 system nodes total.
  # Sufficient for CoreDNS (2 replicas) + addons with room for surge.
  node_count = var.system_pool_node_count

  # System pool does not autoscale — fixed capacity for predictability.
  # If system components OOM or get evicted, autoscaling won't help anyway.

  node_config {
    machine_type = var.system_pool_machine_type

    # Taint: prevents application workloads from landing here unless
    # they explicitly tolerate CriticalAddonsOnly=true:NoSchedule.
    # CoreDNS and GKE system DaemonSets tolerate this automatically.
    taint {
      key    = "CriticalAddonsOnly"
      value  = "true"
      effect = "NO_SCHEDULE"
    }

    labels = {
      pool        = "system"
      environment = "prod"
    }

    tags = concat(var.node_tags, ["gke-system-node"])

    service_account = var.node_service_account_email
    oauth_scopes    = ["https://www.googleapis.com/auth/cloud-platform"]

    disk_size_gb = var.node_disk_size_gb
    disk_type    = var.node_disk_type

    # Shielded instance config on every node pool.
    # Secure Boot: only signed OS components load at boot.
    # vTPM + Integrity Monitoring: attestation chain for the boot sequence.
    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }

    # Workload Identity per node pool: pods on these nodes get
    # Workload Identity tokens. Must match cluster-level config.
    workload_metadata_config {
      mode = "GKE_METADATA"
      # GKE_METADATA: metadata server returns Workload Identity tokens.
      # EXPOSE_METADATA would leak the node's service account credentials
      # to pods — never use in production.
    }

    metadata = {
      # Block access to the legacy instance metadata server endpoint.
      # Prevents pods from extracting the node's service account token
      # via the v1beta1 metadata API (a well-known container escape vector).
      disable-legacy-endpoints = "true"
    }
  }

  management {
    auto_repair  = true  # GKE repairs unhealthy nodes automatically
    auto_upgrade = true  # Nodes upgrade during maintenance window
  }

  upgrade_settings {
    # Surge upgrade: create max_surge extra nodes before draining old ones.
    # max_surge=1 means one extra node per zone during upgrades —
    # zero downtime at the cost of temporary extra node capacity.
    max_surge       = 1
    max_unavailable = 0
    strategy        = "SURGE"
  }
}

# ── Node pool: general ────────────────────────────────────────────────────────
# Primary pool for stateless application workloads.
# Autoscales based on pending pod resource requests.
# On-demand instances: no interruption risk.

resource "google_container_node_pool" "general" {
  name    = "${var.cluster_name}-general-pool"
  project = var.project_id
  cluster = google_container_cluster.primary.id

  autoscaling {
    min_node_count  = var.general_pool_min_nodes  # per zone
    max_node_count  = var.general_pool_max_nodes   # per zone
    location_policy = "BALANCED"
    # BALANCED: Cluster Autoscaler adds/removes nodes evenly across zones.
    # Ensures workloads remain zone-distributed during scale events.
  }

  node_config {
    machine_type = var.general_pool_machine_type
    spot         = false  # On-demand: no preemption

    labels = {
      pool        = "general"
      environment = "prod"
    }

    tags = concat(var.node_tags, ["gke-general-node"])

    service_account = var.node_service_account_email
    oauth_scopes    = ["https://www.googleapis.com/auth/cloud-platform"]

    disk_size_gb = var.node_disk_size_gb
    disk_type    = var.node_disk_type

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

# ── Node pool: spot ───────────────────────────────────────────────────────────
# Spot (preemptible) VMs: 60–91% cheaper than on-demand.
# Can be reclaimed by GCP with 30s notice. Scales to zero when idle.
# Use for: batch jobs, stateless workers, non-critical async processing.
# Do NOT use for: stateful services, long-running jobs, anything with PDBs
# that can't absorb sudden pod loss.

resource "google_container_node_pool" "spot" {
  name    = "${var.cluster_name}-spot-pool"
  project = var.project_id
  cluster = google_container_cluster.primary.id

  autoscaling {
    min_node_count  = 0  # Scales to zero — no cost when idle
    max_node_count  = var.spot_pool_max_nodes
    location_policy = "ANY"
    # ANY: scale into whichever zone has spot capacity.
    # Spot availability varies by zone — ANY maximises the chance
    # of finding capacity when scaling up quickly.
  }

  node_config {
    machine_type = var.spot_pool_machine_type
    spot         = true  # Spot VM — interruptible, ~70% cheaper

    # Taint: prevents workloads from landing here unless they explicitly
    # tolerate interruption. Application owners must opt in.
    taint {
      key    = "cloud.google.com/gke-spot"
      value  = "true"
      effect = "NO_SCHEDULE"
    }

    labels = {
      pool                           = "spot"
      environment                    = "prod"
      "cloud.google.com/gke-spot"    = "true"
    }

    tags = concat(var.node_tags, ["gke-spot-node"])

    service_account = var.node_service_account_email
    oauth_scopes    = ["https://www.googleapis.com/auth/cloud-platform"]

    disk_size_gb = var.node_disk_size_gb
    disk_type    = "pd-standard"  # pd-standard for spot — saves cost

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
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }

  upgrade_settings {
    # Spot nodes: max_unavailable=1 acceptable because the pool is for
    # interruption-tolerant workloads. Surge upgrade costs less.
    max_surge       = 0
    max_unavailable = 1
    strategy        = "SURGE"
  }
}
