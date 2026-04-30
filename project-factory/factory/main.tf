# factory/main.tf
#
# The factory root. This is the only Terraform root that matters
# for day-to-day operations. It:
#   1. Reads every YAML file in registry/projects/
#   2. Iterates over all entries with for_each
#   3. Calls per-project modules: project, networking, iam, budget
#   4. Maintains a single Terraform state for all projects
#
# Adding a project = adding a YAML file + running this apply.
# Removing a project = removing the YAML file + running this apply.
# Updating a project = editing the YAML file + running this apply.
#
# The platform team NEVER manually creates GCP projects, subnets,
# or IAM bindings. Everything flows through this factory.

terraform {
  backend "gcs" {
    bucket = "YOUR_STATE_BUCKET"
    prefix = "project-factory/main"
  }
  required_version = ">= 1.5"
  required_providers {
    google = { source = "hashicorp/google"
    version = ">= 5.0, < 6.0" }
  }
}

provider "google" {
  # Authenticates as the factory SA — needs org-level permissions.
  # In GitLab CI: set GOOGLE_CREDENTIALS env var to SA key JSON
  # or use Workload Identity Federation (preferred — no key files).
}

# ── Registry loading ──────────────────────────────────────────────────────────
# fileset() finds all YAML files in the registry directory.
# yamldecode() parses each file into a Terraform map.
# The result is a map keyed by filename (without extension).
#
# Why fileset + yamldecode rather than a single variables.tf:
#   - Teams add files independently — no merge conflicts on a single file
#   - Each file is self-contained and reviewable in isolation
#   - Schema validation catches errors before plan runs
#   - Adding a project requires zero knowledge of Terraform

locals {
  # Find all .yaml files in the registry
  registry_files = fileset("${path.module}/../registry/projects", "*.yaml")

  # Parse each file and key by filename stem (e.g. "team-payments")
  # trimprefix/trimsuffix removes the path prefix and .yaml extension
  registry = {
    for f in local.registry_files :
    trimsuffix(f, ".yaml") => yamldecode(
      file("${path.module}/../registry/projects/${f}")
    )
  }
}

# ── Per-project resources ─────────────────────────────────────────────────────
# Each module call uses for_each over the full registry.
# Terraform creates one instance of each module per registry entry.
# Adding a new YAML file = Terraform plans to create one new set of resources.
# Removing a YAML file = Terraform plans to destroy that set of resources.

# 1. GCP project + billing + APIs
module "project" {
  for_each = local.registry
  source   = "../modules/project"

  entry              = each.value
  billing_account_id = var.billing_account_id
  org_id             = var.org_id
  folder_id          = var.folder_id
}

# 2. Subnet + Shared VPC attachment + NCC spoke (if connect_to_onprem: true)
module "networking" {
  for_each = local.registry
  source   = "../modules/networking"

  entry           = each.value
  host_project_id = var.host_project_id
  project_id      = module.project[each.key].project_id
  project_number  = module.project[each.key].project_number
  region          = var.region
  ncc_hub_id      = var.ncc_hub_id

  depends_on = [module.project]
}

# 3. Team IAM bindings + node SA
module "iam" {
  for_each = local.registry
  source   = "../modules/iam"

  entry      = each.value
  project_id = module.project[each.key].project_id

  depends_on = [module.project]
}

# 4. Budget alert
module "budget" {
  for_each = local.registry
  source   = "../modules/budget"

  entry              = each.value
  project_id         = module.project[each.key].project_id
  billing_account_id = var.billing_account_id

  depends_on = [module.project]
}
