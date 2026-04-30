# environments/lab/projects/outputs.tf
#
# These outputs are consumed by the host and service environments
# via terraform_remote_state. Avoids hardcoding project IDs in every tfvars.

output "host_project_id" {
  description = "Host project ID — use in environments/lab/host/terraform.tfvars"
  value       = module.projects.project_ids["host"]
}

output "service_project_a_id" {
  description = "Service project A ID — use in environments/lab/host/terraform.tfvars"
  value       = module.projects.project_ids["service-a"]
}

output "service_project_b_id" {
  description = "Service project B ID — use in environments/lab/host/terraform.tfvars"
  value       = module.projects.project_ids["service-b"]
}

output "project_numbers" {
  description = "Project numbers — needed for GKE robot SA email construction"
  value       = module.projects.project_numbers
}

output "next_steps" {
  description = "What to do after applying this workspace"
  value       = <<-EOT
    Projects created. Next steps:

    1. Copy project IDs into host tfvars:
       host_project_id      = "${module.projects.project_ids["host"]}"
       service_project_a_id = "${module.projects.project_ids["service-a"]}"
       service_project_b_id = "${module.projects.project_ids["service-b"]}"

    2. Apply the host environment:
       cd ../host && terraform apply -var-file=terraform.tfvars

    3. Apply service environments:
       cd ../service-a && terraform apply -var-file=terraform.tfvars
       cd ../service-b && terraform apply -var-file=terraform.tfvars

    Alternatively: update the host/service environments to read project IDs
    directly from this workspace's remote state instead of tfvars.
  EOT
}
