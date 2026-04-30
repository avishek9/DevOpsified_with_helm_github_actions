# environments/dev/variables.tf

variable "project_id" {
  description = "GCP project ID where all resources will be created"
  type        = string
}

variable "environment" {
  description = "Environment label (dev / staging / prod). Used in resource names."
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be dev, staging, or prod."
  }
}

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
    name          = string
    region        = string
    ip_cidr_range = string
    description   = optional(string, "")
    secondary_ranges = optional(list(object({
      range_name    = string
      ip_cidr_range = string
    })), [])
  }))
}