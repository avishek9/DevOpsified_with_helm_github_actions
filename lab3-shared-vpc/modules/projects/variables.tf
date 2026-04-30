# modules/projects/variables.tf

variable "billing_account_id" {
  description = <<-EOT
    GCP billing account ID to link to all created projects.
    Format: XXXXXX-XXXXXX-XXXXXX
    Find yours: gcloud billing accounts list
    All projects must have billing linked or API enablement fails silently.
  EOT
  type = string
}

variable "org_id" {
  description = <<-EOT
    GCP organisation ID. Projects are created under this org.
    Find yours: gcloud organizations list
    If you don't have an org (personal account), use folder_id instead
    and set org_id = null.
  EOT
  type    = string
  default = null
}

variable "folder_id" {
  description = <<-EOT
    Optional GCP folder ID to create projects under.
    Recommended for enterprise: one folder per environment or team.
    Format: folders/XXXXXXXXX
    If provided, org_id is ignored for project placement.
    If neither org_id nor folder_id are set, projects go under your
    account's default location — only works for personal accounts.
  EOT
  type    = string
  default = null
}

variable "projects" {
  description = <<-EOT
    Map of projects to create. Each entry:
      project_id:   Globally unique GCP project ID (max 30 chars,
                    lowercase letters/numbers/hyphens, must start with letter).
                    Cannot be changed after creation.
      name:         Human-readable display name (can be changed later).
      apis:         List of APIs to enable on creation.
      labels:       Resource labels for cost attribution and governance.
      is_host:      true if this project will be a Shared VPC host.
                    Enables compute API and marks it for Shared VPC setup.
  EOT
  type = map(object({
    project_id = string
    name       = string
    apis       = optional(list(string), [])
    labels     = optional(map(string), {})
    is_host    = optional(bool, false)
  }))
}
