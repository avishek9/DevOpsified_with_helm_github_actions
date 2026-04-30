# modules/gke/variables.tf

# ── Project & location ────────────────────────────────────────────────────────

variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "region" {
  description = <<-EOT
    GCP region for the regional cluster.
    Regional clusters run control plane replicas across all three zones
    in this region. A single zone failure does not interrupt the API server.
  EOT
  type    = string
  default = "us-central1"
}

variable "network" {
  description = "VPC network name or self_link to host the cluster"
  type        = string
}

variable "subnetwork" {
  description = "Subnetwork name or self_link for cluster nodes"
  type        = string
}

# ── Cluster identity ──────────────────────────────────────────────────────────

variable "cluster_name" {
  description = "Name of the GKE cluster"
  type        = string
}

variable "description" {
  description = "Human-readable cluster description"
  type        = string
  default     = ""
}

# ── Networking ────────────────────────────────────────────────────────────────

variable "pods_range_name" {
  description = <<-EOT
    Name of the secondary subnet range to use for pod IPs.
    Must match a secondary range already created on the subnetwork.
    GKE will NOT create this range — it must exist before cluster creation.
  EOT
  type = string
}

variable "services_range_name" {
  description = <<-EOT
    Name of the secondary subnet range to use for Service ClusterIPs.
    Must match a secondary range already created on the subnetwork.
  EOT
  type = string
}

variable "master_ipv4_cidr_block" {
  description = <<-EOT
    CIDR block for the private cluster control plane.
    Must be a /28 block from 172.16.0.0/12 or 10.x.x.x ranges.
    Cannot overlap with any subnet or peered network range.
    Cannot be changed after cluster creation.
    Example: "172.16.0.0/28"
  EOT
  type = string

  validation {
    condition     = can(cidrnetmask(var.master_ipv4_cidr_block))
    error_message = "master_ipv4_cidr_block must be a valid CIDR."
  }
}

variable "master_authorized_networks" {
  description = <<-EOT
    List of CIDR blocks authorised to reach the private cluster API server.
    For fully private clusters (no public endpoint), set this to [].
    For clusters accessed from on-prem or Cloud Shell, include those CIDRs.
    Each entry: { cidr_block, display_name }
  EOT
  type = list(object({
    cidr_block   = string
    display_name = string
  }))
  default = []
}

variable "enable_private_endpoint" {
  description = <<-EOT
    true  = no public endpoint — API server only reachable via internal VPC IP.
             Requires Cloud Shell, bastion VM, or IAP tunnel for kubectl access.
    false = public endpoint exists but is protected by master_authorized_networks.
             Easier for CI/CD pipelines with static IPs.
    Production recommendation: true.
  EOT
  type    = bool
  default = true
}

# ── Release channel ───────────────────────────────────────────────────────────

variable "release_channel" {
  description = <<-EOT
    GKE release channel controls automatic version management.
    RAPID:   latest features, less validation — dev/test only.
    REGULAR: balanced stability/features — most production workloads.
    STABLE:  maximum stability, slowest updates — regulated workloads.
    Never use UNSPECIFIED (no auto-upgrades, falls out of support).
  EOT
  type    = string
  default = "REGULAR"

  validation {
    condition     = contains(["RAPID", "REGULAR", "STABLE"], var.release_channel)
    error_message = "release_channel must be RAPID, REGULAR, or STABLE."
  }
}

# ── Maintenance window ────────────────────────────────────────────────────────

variable "maintenance_start_time" {
  description = <<-EOT
    RFC3339 time for the start of the recurring maintenance window.
    GKE may perform upgrades and repairs during this window.
    Format: "2024-01-01T02:00:00Z" (time portion matters, date is ignored for recurring).
    Choose off-peak hours for your workload timezone.
  EOT
  type    = string
  default = "2024-01-01T02:00:00Z"
}

variable "maintenance_end_time" {
  description = "RFC3339 time for the end of the recurring maintenance window"
  type        = string
  default     = "2027-01-01T06:00:00Z"
}

variable "maintenance_recurrence" {
  description = <<-EOT
    RFC5545 RRULE for maintenance recurrence.
    "FREQ=WEEKLY;BYDAY=SA,SU" = weekends only.
    "FREQ=DAILY"               = every day.
  EOT
  type    = string
  default = "FREQ=WEEKLY;BYDAY=SA,SU"
}

# ── Node pools ────────────────────────────────────────────────────────────────

variable "system_pool_machine_type" {
  description = "Machine type for the system node pool (cluster-critical addons)"
  type        = string
  default     = "e2-standard-4"
}

variable "system_pool_node_count" {
  description = "Number of nodes per zone in the system pool (regional = ×3)"
  type        = number
  default     = 1
}

variable "general_pool_machine_type" {
  description = "Machine type for the general workload node pool"
  type        = string
  default     = "n2-standard-8"
}

variable "general_pool_min_nodes" {
  description = "Minimum nodes per zone for general pool autoscaler"
  type        = number
  default     = 1
}

variable "general_pool_max_nodes" {
  description = "Maximum nodes per zone for general pool autoscaler"
  type        = number
  default     = 10
}

variable "spot_pool_machine_type" {
  description = "Machine type for the spot (preemptible) workload node pool"
  type        = string
  default     = "n2-standard-8"
}

variable "spot_pool_max_nodes" {
  description = "Maximum nodes per zone for spot pool autoscaler"
  type        = number
  default     = 5
}

variable "node_service_account_email" {
  description = <<-EOT
    Email of the service account attached to GKE nodes.
    This SA needs: roles/logging.logWriter, roles/monitoring.metricWriter,
    roles/monitoring.viewer, roles/artifactregistry.reader.
    Workload Identity means individual pods get their own GCP identity —
    the node SA is a fallback that should have minimal permissions.
  EOT
  type = string
}

variable "node_disk_size_gb" {
  description = "Boot disk size in GB for all node pools"
  type        = number
  default     = 100
}

variable "node_disk_type" {
  description = "Boot disk type: pd-standard, pd-ssd, pd-balanced"
  type        = string
  default     = "pd-ssd"
}

# ── Binary Authorization ──────────────────────────────────────────────────────

variable "binary_authorization_mode" {
  description = <<-EOT
    Binary Authorization evaluation mode.
    DISABLED:        No image policy enforcement.
    PROJECT_SINGLETON_POLICY_ENFORCE: Enforce the project-level BinAuthz policy.
    Use PROJECT_SINGLETON_POLICY_ENFORCE for production.
    Configure the actual policy separately via google_binary_authorization_policy.
  EOT
  type    = string
  default = "PROJECT_SINGLETON_POLICY_ENFORCE"

  validation {
    condition     = contains(["DISABLED", "PROJECT_SINGLETON_POLICY_ENFORCE"], var.binary_authorization_mode)
    error_message = "binary_authorization_mode must be DISABLED or PROJECT_SINGLETON_POLICY_ENFORCE."
  }
}

# ── Labels & tags ─────────────────────────────────────────────────────────────

variable "cluster_labels" {
  description = "Labels applied to the GKE cluster resource"
  type        = map(string)
  default     = {}
}

variable "node_tags" {
  description = <<-EOT
    Network tags applied to all nodes.
    Used to target firewall rules at nodes without hardcoding IP ranges.
    Minimum: a tag matching your firewall rule for health checks.
  EOT
  type    = list(string)
  default = []
}
