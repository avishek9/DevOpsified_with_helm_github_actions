# Lab 1 — Custom-mode VPC with Terraform

## What this builds

- Custom-mode VPC (no auto-created subnets)
- Two regional subnets (us-central1 + europe-west1) each with:
  - Primary range for VM instances
  - Secondary range for GKE pods
  - Secondary range for GKE services
  - Private Google Access enabled
- Firewall rules using network tags:
  - Allow SSH from IAP ranges only (no public SSH)
  - Allow HTTP/HTTPS on tagged web servers
  - Allow internal traffic between tagged app tiers
  - Deny all other ingress (implicit, but made explicit)
- Cloud NAT for outbound internet from private VMs

## File structure

```
lab1-vpc/
├── README.md
├── modules/
│   └── vpc/
│       ├── main.tf          # VPC, subnets, NAT
│       ├── firewall.tf      # All firewall rules
│       ├── variables.tf     # Module inputs
│       └── outputs.tf       # Module outputs
└── environments/
    └── dev/
        ├── main.tf          # Root module — calls vpc module
        ├── variables.tf     # Environment-level variables
        ├── terraform.tfvars # Actual values (gitignored in real use)
        ├── backend.tf       # GCS remote state config
        └── outputs.tf       # Root outputs
```

## Prerequisites

1. GCP project with billing enabled
2. APIs enabled: `compute.googleapis.com`
3. Service account with `compute.networkAdmin` role
4. GCS bucket for Terraform state

## Usage

```bash
cd environments/dev

# Initialise with remote state
terraform init

# Preview what will be created
terraform plan -var-file=terraform.tfvars

# Apply
terraform apply -var-file=terraform.tfvars

# Verify — list created subnets
gcloud compute networks subnets list \
  --filter="network=lab1-vpc" \
  --format="table(name,region,ipCidrRange,privateIpGoogleAccess)"

# Verify firewall rules
gcloud compute firewall-rules list \
  --filter="network=lab1-vpc" \
  --format="table(name,direction,priority,sourceRanges,targetTags,allowed)"
```

## Post-apply verification checklist

- [ ] VPC exists and is custom-mode (not auto-mode)
- [ ] Both subnets have Private Google Access = true
- [ ] Both subnets have two secondary ranges each
- [ ] Firewall rules use tags not IP ranges for app-tier targeting
- [ ] No firewall rule allows 0.0.0.0/0 ingress on port 22
- [ ] Cloud NAT exists for each region
- [ ] Test VM without public IP can reach storage.googleapis.com
