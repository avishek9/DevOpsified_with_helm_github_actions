# environments/dev/main.tf
#
# Root module for the dev environment.
# Calls the vpc module with dev-specific subnet and firewall configuration.
#
# IP plan used in this lab:
#
#   us-central1 subnet:
#     Primary:           10.10.0.0/20  (4094 VM IPs)
#     Pods (secondary):  10.100.0.0/18 (16382 pod IPs — GKE needs large range)
#     Services:          10.200.0.0/22 (1022 service IPs)
#
#   europe-west1 subnet:
#     Primary:           10.20.0.0/20  (4094 VM IPs)
#     Pods (secondary):  10.104.0.0/18 (16382 pod IPs)
#     Services:          10.200.4.0/22 (1022 service IPs)
#
# All ranges are non-overlapping and fall within RFC1918 10.0.0.0/8.
# They do not overlap with common on-prem ranges (192.168.x.x, 172.16.x.x).
# Secondary ranges are sized for GKE — /18 for pods (GKE default max
# 110 pods/node × 110 nodes = 12100 pod IPs minimum).
locals {
  # This loops through your subnets list and pulls out every ip_cidr_range
  all_subnet_cidrs = [for s in var.subnets : s.ip_cidr_range]
}
module "vpc" {
  source = "../../modules/vpc"

  project_id   = var.project_id
  vpc_name     = "lab1-vpc-${var.environment}"
  description  = "Lab 1 VPC — ${var.environment} environment. Custom mode, two regions, GKE-ready secondary ranges."
  routing_mode = "GLOBAL"

  # ── Subnets ──────────────────────────────────────────────────────────────
  subnets = var.subnets

  # ── Firewall ──────────────────────────────────────────────────────────────

  enable_iap_ssh    = true
  enable_http_https = true

  # Internal source ranges = all primary subnet CIDRs in this VPC.
  # VMs tagged 'allow-internal' accept traffic from these ranges.
  # Update this list when adding new subnets.
  internal_source_ranges = local.all_subnet_cidrs # europe-west1 primary
  # Do NOT include secondary ranges here — pod/service traffic
  # should go through the application layer, not a blanket allow.

  enable_deny_all_ingress = true

  # ── NAT ───────────────────────────────────────────────────────────────────

  create_nat     = true
  nat_log_filter = "ERRORS_ONLY"
}

# ── Test VM (optional — useful for Lab 1 verification) ───────────────────────
# Uncomment this block after applying the VPC to test:
#   1. Private Google Access (VM has no external IP but can reach GCS)
#   2. IAP SSH (connect with: gcloud compute ssh test-vm --tunnel-through-iap)
#   3. Internal connectivity between VMs

# resource "google_compute_instance" "test_vm" {
#   name         = "lab1-test-vm"
#   project      = var.project_id
#   zone         = "us-central1-a"
#   machine_type = "e2-micro"  # Free tier eligible
#
#   boot_disk {
#     initialize_params {
#       image = "debian-cloud/debian-12"
#       size  = 20
#       type  = "pd-standard"
#     }
#   }
#
#   network_interface {
#     # Attach to the us-central1 subnet — no external IP
#     subnetwork = module.vpc.subnet_self_links["subnet-us-central1-${var.environment}"]
#     # access_config {} block is intentionally absent = no external IP
#   }
#
#   # Tags control which firewall rules apply to this VM
#   tags = ["allow-ssh", "allow-internal"]
#
#   # Verify Private Google Access works:
#   metadata_startup_script = <<-EOT
#     #!/bin/bash
#     # This should succeed even without an external IP (PGA handles it)
#     curl -s https://storage.googleapis.com/ > /var/log/pga-test.log 2>&1
#     echo "PGA test complete. Exit code: $?" >> /var/log/pga-test.log
#   EOT
#
#   service_account {
#     scopes = ["https://www.googleapis.com/auth/cloud-platform"]
#   }
# }
