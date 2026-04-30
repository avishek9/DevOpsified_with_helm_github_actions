# modules/gke-service/variables.tf

variable "service_project_id" {
  description = "Project ID where the GKE cluster will be created"
  type        = string
}

variable "host_project_id" {
  description = "Project ID of the Shared VPC host project"
  type        = string
}

variable "cluster_name" {
  description = "Name for the GKE cluster"
  type        = string
}

variable "region" {
  description = "GCP region for the regional cluster"
  type        = string
  default     = "us-central1"
}

# ── Shared VPC networking ─────────────────────────────────────────────────────

variable "shared_vpc_self_link" {
  description = <<-EOT
    Self_link of the shared VPC network in the host project.
    Format: https://www.googleapis.com/compute/v1/projects/HOST/global/networks/NAME
    Use the output from the shared-vpc module — not just the network name,
    which would be ambiguous when the cluster is in a different project.
  EOT
  type = string
}

variable "subnet_self_link" {
  description = <<-EOT
    Self_link of the subnet (in the host project) to place GKE nodes in.
    Must be a subnet the service project has been granted compute.networkUser on.
    Using self_link (not name) ensures GKE resolves the correct subnet
    even though the subnet lives in a different project.
  EOT
  type = string
}

variable "pods_range_name" {
  description = "Name of the secondary range for pod IPs on the shared subnet"
  type        = string
}

variable "services_range_name" {
  description = "Name of the secondary range for service IPs on the shared subnet"
  type        = string
}

variable "master_ipv4_cidr_block" {
  description = "/28 CIDR for GKE control plane. Cannot overlap with any subnet or peered range."
  type        = string
}

variable "master_authorized_networks" {
  description = "CIDR blocks allowed to reach the cluster API server"
  type = list(object({
    cidr_block   = string
    display_name = string
  }))
  default = []
}

variable "enable_private_endpoint" {
  description = "Restrict API server to internal VPC IP only"
  type        = bool
  default     = true
}

# ── Cluster config ────────────────────────────────────────────────────────────

variable "release_channel" {
  description = "GKE release channel: RAPID, REGULAR, or STABLE"
  type        = string
  default     = "REGULAR"
}

variable "node_machine_type" {
  description = "Machine type for the default workload node pool"
  type        = string
  default     = "e2-standard-4"
}

variable "node_min_count" {
  description = "Minimum nodes per zone"
  type        = number
  default     = 1
}

variable "node_max_count" {
  description = "Maximum nodes per zone"
  type        = number
  default     = 5
}

variable "cluster_labels" {
  description = "Labels applied to the cluster resource"
  type        = map(string)
  default     = {}
}
