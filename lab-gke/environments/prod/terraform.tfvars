# environments/prod/terraform.tfvars
# Replace all values before applying.

project_id  = "project-ee7e41c4-c112-4d32-888"
region      = "us-central1"

# From lab1-vpc module outputs:
vpc_name            = "lab1-vpc-dev"
subnet_name         = "subnet-us-central1-dev"
pods_range_name     = "subnet-us-central1-dev-pods"
services_range_name = "subnet-us-central1-dev-services"

# /28 for control plane — must not overlap anything.
# 172.16.0.0/28 is a safe default if not already used.
master_ipv4_cidr_block = "172.16.0.0/28"
