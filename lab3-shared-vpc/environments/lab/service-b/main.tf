# environments/lab/service-b/main.tf
#
# Service project B — no GKE cluster.
# Demonstrates:
#   1. The subnet IAM binding from the host project gives access to subnet-b only
#   2. Team B can deploy VMs into subnet-service-b
#   3. Team B cannot see or use subnet-service-a
#   4. Both teams share the same physical VPC but are logically isolated
#
# This is the "IAM binding verification" part of Lab 3.

resource "google_project_service" "compute" {
  project            = var.service_project_id
  service            = "compute.googleapis.com"
  disable_on_destroy = false
}

# ── Read host project state ───────────────────────────────────────────────────

data "terraform_remote_state" "host" {
  backend = "gcs"
  config = {
    bucket = var.state_bucket
    prefix = "lab3-shared-vpc/host"
  }
}

# ── Verification VM ───────────────────────────────────────────────────────────
# A minimal VM in subnet-service-b to demonstrate that:
#   - Service project B can deploy into its own subnet
#   - The VM has no external IP (private node, uses Cloud NAT for egress)
#   - The VM cannot be reached from service-a subnet without a firewall rule
#
# Uncomment to create. Costs ~$5/month on e2-micro.

# resource "google_compute_instance" "team_b_vm" {
#   name         = "team-b-test-vm"
#   project      = var.service_project_id
#   zone         = "${var.region}-a"
#   machine_type = "e2-micro"
#
#   boot_disk {
#     initialize_params {
#       image = "debian-cloud/debian-12"
#       size  = 20
#     }
#   }
#
#   network_interface {
#     # Use subnet self_link from host project state.
#     # This is the ONLY subnet this project can access.
#     subnetwork = data.terraform_remote_state.host.outputs.subnet_self_links["service-b"]
#     # No access_config block = no external IP
#   }
#
#   tags = ["allow-ssh", "allow-internal"]
#
#   # Test: Private Google Access via PGA (no NAT needed for Google APIs)
#   metadata_startup_script = <<-EOT
#     #!/bin/bash
#     curl -s https://storage.googleapis.com/ > /tmp/pga-test.txt
#   EOT
#
#   service_account {
#     scopes = ["https://www.googleapis.com/auth/cloud-platform"]
#   }
#
#   depends_on = [google_project_service.compute]
# }

# ── Outputs ───────────────────────────────────────────────────────────────────

output "subnet_b_self_link" {
  description = "The only subnet service project B can access"
  value       = data.terraform_remote_state.host.outputs.subnet_self_links["service-b"]
}

output "isolation_verification_commands" {
  description = "Commands to verify subnet isolation between service projects"
  value       = <<-EOT
    # Service project B should see ONLY subnet-service-b:
    gcloud compute networks subnets list-usable \
      --project=${var.service_project_id}

    # Attempting to use subnet-service-a from project B should fail:
    # gcloud compute instances create test-vm \
    #   --project=${var.service_project_id} \
    #   --zone=${var.region}-a \
    #   --subnet=subnet-service-a \
    #   --no-address
    # Expected error: "User does not have access to subnet subnet-service-a"

    # Confirm the host project owns all firewall rules
    # (service project B cannot create firewall rules in the shared VPC):
    gcloud compute firewall-rules list --project=${var.host_project_id} \
      --filter="network=shared-vpc"

    # Try creating a firewall rule from service project B — this MUST fail:
    # gcloud compute firewall-rules create test-fw \
    #   --project=${var.service_project_id} \
    #   --network=shared-vpc \
    #   --allow=tcp:80
    # Expected error: permission denied — service projects cannot modify the VPC
  EOT
}
