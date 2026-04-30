# modules/shared-vpc/variables.tf

variable "host_project_id" {
  description = <<-EOT
    Project ID of the Shared VPC host project.
    This project owns the VPC, subnets, firewall rules, and
    Cloud Router/NAT. The network team should own this project.
    Service project teams cannot modify network resources here.
  EOT
  type = string
}

variable "vpc_name" {
  description = "Name of the shared VPC network"
  type        = string
  default     = "shared-vpc"
}

variable "region" {
  description = "Primary region for subnets and Cloud Router"
  type        = string
  default     = "us-central1"
}

variable "routing_mode" {
  description = "VPC routing mode — GLOBAL recommended for hybrid connectivity"
  type        = string
  default     = "GLOBAL"

  validation {
    condition     = contains(["REGIONAL", "GLOBAL"], var.routing_mode)
    error_message = "routing_mode must be REGIONAL or GLOBAL."
  }
}

# ── Service project definitions ───────────────────────────────────────────────

variable "service_projects" {
  description = <<-EOT
    Map of service projects to attach to this Shared VPC.
    Each entry:
      project_id:         GCP project ID of the service project
      subnet_name:        Name of the subnet this project gets access to
      ip_cidr_range:      Primary CIDR for this project's subnet
      pods_cidr:          Secondary range for GKE pod IPs
      services_cidr:      Secondary range for GKE service IPs
      description:        Human-readable description for the subnet
  EOT
  type = map(object({
    project_id    = string
    subnet_name   = string
    ip_cidr_range = string
    pods_cidr     = string
    services_cidr = string
    description   = optional(string, "")
  }))
}

# ── Firewall ──────────────────────────────────────────────────────────────────

variable "enable_iap_ssh" {
  description = "Allow SSH from IAP ranges to VMs tagged allow-ssh"
  type        = bool
  default     = true
}

variable "internal_ranges" {
  description = <<-EOT
    CIDR ranges treated as internal — used in allow-internal firewall rule.
    Should cover all subnet primary CIDRs in the shared VPC.
    VMs tagged allow-internal accept traffic from these ranges.
  EOT
  type    = list(string)
  default = []
}

# ── NAT ───────────────────────────────────────────────────────────────────────

variable "create_nat" {
  description = "Create Cloud NAT for private VM internet egress"
  type        = bool
  default     = true
}
