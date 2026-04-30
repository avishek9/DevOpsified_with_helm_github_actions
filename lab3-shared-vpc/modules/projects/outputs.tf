# modules/projects/outputs.tf

output "project_ids" {
  description = "Map of project key → project ID"
  value       = { for k, v in google_project.projects : k => v.project_id }
}

output "project_numbers" {
  description = <<-EOT
    Map of project key → project number.
    Project number is needed for:
      - GKE robot service account emails
      - Workload Identity pool references
      - Some IAM member formats
    Format: numeric string e.g. "123456789"
  EOT
  value = { for k, v in google_project.projects : k => v.number }
}

output "project_names" {
  description = "Map of project key → display name"
  value       = { for k, v in google_project.projects : k => v.name }
}
