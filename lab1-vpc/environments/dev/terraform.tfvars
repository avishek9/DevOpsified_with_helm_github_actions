# environments/dev/terraform.tfvars
#
# Actual variable values for the dev environment.
# In a real repo: add terraform.tfvars to .gitignore.
# Use a secrets manager or CI/CD variable injection for project_id
# if it is considered sensitive information in your organisation.

project_id  = "project-ee7e41c4-c112-4d32-888" # Replace with your actual project ID
environment = "dev"
subnets = [
  {
    name          = "subnet-us-central1-dev"
    region        = "us-central1"
    ip_cidr_range = "10.10.0.0/20"
    description   = "Primary subnet for us-central1 workloads"
    secondary_ranges = [
      {
        range_name    = "subnet-us-central1-dev-pods"
        ip_cidr_range = "10.100.0.0/18"
      },
      {
        range_name    = "subnet-us-central1-dev-services"
        ip_cidr_range = "10.200.0.0/22"
      }
    ]
  },
  {
    name          = "subnet-europe-west1-dev"
    region        = "europe-west1"
    ip_cidr_range = "10.20.0.0/20"
    description   = "Primary subnet for europe-west1 workloads"
    secondary_ranges = [
      {
        range_name    = "subnet-europe-west1-dev-pods"
        ip_cidr_range = "10.104.0.0/18"
      },
      {
        range_name    = "subnet-europe-west1-dev-services"
        ip_cidr_range = "10.200.4.0/22"
      }
    ]
  }
]
