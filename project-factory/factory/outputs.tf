# factory/outputs.tf

output "project_inventory" {
  description = <<-EOT
    Full inventory of all factory-managed projects.
    Use this as an input to other systems: service catalogues,
    monitoring dashboards, cost attribution reports.
  EOT
  value = {
    for key, entry in local.registry : key => {
      project_id     = module.project[key].project_id
      project_number = module.project[key].project_number
      team           = entry.project.team
      environment    = entry.project.environment
      cost_center    = entry.project.cost_center
      subnet         = module.networking[key].subnet_self_link
      on_prem_spoke  = module.networking[key].ncc_spoke_id
      node_sa        = module.iam[key].node_sa_email
    }
  }
}

output "migration_status" {
  description = <<-EOT
    Projects currently connected to on-prem via NCC spoke.
    These are workloads still in migration — remove connect_to_onprem
    flag from their registry entry once cutover is complete.
  EOT
  value = {
    for key, entry in local.registry :
    key => module.project[key].project_id
    if try(entry.networking.connect_to_onprem, false) == true
  }
}

output "total_projects" {
  description = "Total number of projects managed by this factory"
  value       = length(local.registry)
}
