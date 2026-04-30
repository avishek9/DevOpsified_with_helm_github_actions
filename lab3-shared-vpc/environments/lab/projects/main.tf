# environments/lab/projects/main.tf
#
# Creates all three GCP projects for Lab 3.
# Run this workspace first — all other workspaces depend on these projects.

module "projects" {
  source = "../../../modules/projects"

  billing_account_id = var.billing_account_id
  org_id             = var.org_id
  folder_id          = var.folder_id

  projects = {
    # ── Host project ─────────────────────────────────────────────────────────
    # Owns the Shared VPC. Network team manages this project.
    # Service projects cannot modify network resources here.
    "host" = {
      project_id = "${var.project_id_prefix}-host"
      name       = "Lab3 Host Project"
      is_host    = true
      apis = [
        "compute.googleapis.com",
        "container.googleapis.com",
        "servicenetworking.googleapis.com",
      ]
      labels = {
        role        = "host"
        team        = "network"
        environment = "lab"
      }
    }

    # ── Service project A ─────────────────────────────────────────────────────
    # Runs a GKE cluster using the host project's shared subnet.
    # Team A owns this project and all resources within it.
    # Cannot see or modify network resources in the host project.
    "service-a" = {
      project_id = "${var.project_id_prefix}-svc-a"
      name       = "Lab3 Service Project A"
      is_host    = false
      apis = [
        "compute.googleapis.com",
        "container.googleapis.com",
        "artifactregistry.googleapis.com",
        "cloudresourcemanager.googleapis.com",
        "iam.googleapis.com",
      ]
      labels = {
        role        = "service"
        team        = "team-a"
        environment = "lab"
      }
    }

    # ── Service project B ─────────────────────────────────────────────────────
    # No GKE cluster — demonstrates subnet IAM isolation only.
    # Team B can only use subnet-service-b, not subnet-service-a.
    "service-b" = {
      project_id = "${var.project_id_prefix}-svc-b"
      name       = "Lab3 Service Project B"
      is_host    = false
      apis = [
        "compute.googleapis.com",
        "cloudresourcemanager.googleapis.com",
      ]
      labels = {
        role        = "service"
        team        = "team-b"
        environment = "lab"
      }
    }
  }
}
