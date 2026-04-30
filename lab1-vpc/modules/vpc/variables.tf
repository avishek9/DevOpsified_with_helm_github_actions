# modules/vpc/variables.tf

variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "vpc_name" {
  description = "Name for the VPC network"
  type        = string
}

variable "description" {
  description = "Human-readable description for the VPC"
  type        = string
  default     = ""
}

# ── Routing ───────────────────────────────────────────────────────────────────

variable "routing_mode" {
  description = <<-EOT
    VPC dynamic routing mode.
    REGIONAL: Cloud Router only learns/advertises routes in its own region.
    GLOBAL:   Cloud Router learns/advertises all subnets across all regions.
    Use GLOBAL when you have hybrid connectivity (VPN/Interconnect) and want
    on-prem to reach subnets in multiple regions via one Cloud Router.
  EOT
  type    = string
  default = "GLOBAL"

  validation {
    condition     = contains(["REGIONAL", "GLOBAL"], var.routing_mode)
    error_message = "routing_mode must be REGIONAL or GLOBAL."
  }
}

# ── Subnets ───────────────────────────────────────────────────────────────────

variable "subnets" {
  description = <<-EOT
    List of subnet configurations. Each subnet supports:
    - name:              Subnet name (required)
    - region:            GCP region (required)
    - ip_cidr_range:     Primary CIDR for VM instances (required)
    - secondary_ranges:  List of {range_name, ip_cidr_range} for GKE (optional)
    - description:       Human-readable label (optional)

    Secondary ranges are required for GKE clusters that use alias IPs.
    Naming convention for secondary ranges:
      <subnet-name>-pods     → GKE pod CIDR
      <subnet-name>-services → GKE service CIDR
  EOT
  type = list(object({
    name            = string
    region          = string
    ip_cidr_range   = string
    description     = optional(string, "")
    secondary_ranges = optional(list(object({
      range_name    = string
      ip_cidr_range = string
    })), [])
  }))
}

# ── Firewall ──────────────────────────────────────────────────────────────────

variable "enable_iap_ssh" {
  description = <<-EOT
    Allow SSH from Google IAP ranges (35.235.240.0/20) to VMs tagged 'allow-ssh'.
    This is the secure pattern — never allow 0.0.0.0/0 on port 22.
  EOT
  type    = bool
  default = true
}

variable "enable_http_https" {
  description = "Allow HTTP (80) and HTTPS (443) ingress to VMs tagged 'allow-web'"
  type        = bool
  default     = true
}

variable "internal_source_ranges" {
  description = <<-EOT
    CIDR ranges considered internal for allow-internal firewall rule.
    Should cover all subnet primary ranges in this VPC.
    VMs tagged 'allow-internal' will accept traffic from these ranges.
  EOT
  type    = list(string)
  default = []
}

variable "enable_deny_all_ingress" {
  description = <<-EOT
    Create an explicit deny-all ingress rule at priority 65534.
    GCP has an implicit deny at 65535, but making it explicit ensures
    it appears in audit logs and firewall rule listings.
    Recommended: true for production.
  EOT
  type    = bool
  default = true
}

# ── Cloud NAT ─────────────────────────────────────────────────────────────────

variable "create_nat" {
  description = <<-EOT
    Create Cloud NAT for each subnet region.
    Required for VMs without external IPs to reach the internet.
    Private Google Access (enabled on each subnet) handles Google API
    traffic without NAT — NAT is only needed for non-Google destinations.
  EOT
  type    = bool
  default = true
}

variable "nat_log_filter" {
  description = <<-EOT
    Cloud NAT logging filter.
    ALL:              Log all NAT translations and errors.
    ERRORS_ONLY:      Log only translation errors.
    TRANSLATIONS_ONLY: Log all translations, no errors.
  EOT
  type    = string
  default = "ERRORS_ONLY"

  validation {
    condition     = contains(["ALL", "ERRORS_ONLY", "TRANSLATIONS_ONLY"], var.nat_log_filter)
    error_message = "nat_log_filter must be ALL, ERRORS_ONLY, or TRANSLATIONS_ONLY."
  }
}
