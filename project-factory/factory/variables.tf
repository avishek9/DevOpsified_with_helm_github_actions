# factory/variables.tf

variable "billing_account_id" {
  description = "GCP billing account ID linked to all factory-created projects"
  type        = string
}

variable "org_id" {
  description = "GCP organisation ID"
  type        = string
  default     = null
}

variable "folder_id" {
  description = "Folder to create all projects under (recommended)"
  type        = string
  default     = null
}

variable "host_project_id" {
  description = "Shared VPC host project ID — subnets are created here"
  type        = string
}

variable "region" {
  description = "Default GCP region for subnets and GKE clusters"
  type        = string
  default     = "us-central1"
}

variable "ncc_hub_id" {
  description = <<-EOT
    NCC hub ID for on-prem connectivity spokes.
    Required only if any registry entry has connect_to_onprem: true.
    Format: projects/PROJECT/locations/global/hubs/HUB_NAME
  EOT
  type    = string
  default = null
}
