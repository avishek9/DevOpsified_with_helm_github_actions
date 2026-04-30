# environments/lab/projects/variables.tf

variable "billing_account_id" {
  description = "GCP billing account ID. Find with: gcloud billing accounts list"
  type        = string
}

variable "org_id" {
  description = <<-EOT
    GCP organisation ID. Find with: gcloud organizations list
    Set to null if using a personal GCP account with no org.
    In that case set folder_id instead, or leave both null.
  EOT
  type    = string
  default = null
}

variable "folder_id" {
  description = <<-EOT
    Optional folder to create projects under.
    Recommended: create a "lab3" folder under your org and put all
    three projects there for clean isolation and easy deletion.
    Format: folders/XXXXXXXXX (include the "folders/" prefix).
    Leave null to create under the org root or your personal account.
  EOT
  type    = string
  default = null
}

variable "project_id_prefix" {
  description = <<-EOT
    Prefix for all project IDs in this lab.
    Full IDs will be: PREFIX-host, PREFIX-svc-a, PREFIX-svc-b.
    Must be globally unique — GCP project IDs are a global namespace.
    Recommended: use your username or org shortname, e.g. "jsmith-lab3"
    Max prefix length: 20 chars (total ID must be ≤ 30 chars).
  EOT
  type = string

  validation {
    condition     = length(var.project_id_prefix) <= 20 && can(regex("^[a-z][a-z0-9-]*$", var.project_id_prefix))
    error_message = "project_id_prefix must be ≤ 20 chars, start with a letter, and contain only lowercase letters, numbers, and hyphens."
  }
}
