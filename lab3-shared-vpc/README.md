# Lab 3 — Shared VPC with GKE in a Service Project

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│  Host Project (network team owns this)                      │
│                                                             │
│  ┌─────────────────────────────────────────────────────┐   │
│  │  Shared VPC                                         │   │
│  │                                                     │   │
│  │  subnet-service-a  10.10.0.0/20  us-central1       │   │
│  │    pods:     10.100.0.0/18                          │   │
│  │    services: 10.200.0.0/22                          │   │
│  │                                                     │   │
│  │  subnet-service-b  10.20.0.0/20  us-central1       │   │
│  │    pods:     10.104.0.0/18                          │   │
│  │    services: 10.200.4.0/22                          │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                             │
│  Cloud Router + Cloud NAT (for private node egress)        │
│  Firewall rules (IAP SSH, health checks, internal)         │
└────────────────┬──────────────────┬─────────────────────────┘
                 │                  │
    subnet IAM   │                  │  subnet IAM
    binding      │                  │  binding
                 ▼                  ▼
┌────────────────────┐  ┌────────────────────┐
│  Service Project A │  │  Service Project B │
│  (team-a)          │  │  (team-b)          │
│                    │  │                    │
│  GKE cluster       │  │  (no GKE — shows   │
│  private nodes     │  │   IAM binding only)│
│  Workload Identity │  │                    │
│                    │  │                    │
│  Uses:             │  │  Uses:             │
│  subnet-service-a  │  │  subnet-service-b  │
│  (cannot see B's)  │  │  (cannot see A's)  │
└────────────────────┘  └────────────────────┘
```

## What Shared VPC actually enforces

- Service projects can deploy resources INTO subnets they have been granted access to
- Service projects CANNOT modify the VPC, create subnets, or change firewall rules
- Service projects CANNOT see each other's subnets (IAM is per-subnet, not VPC-wide)
- Billing for compute resources stays in the service project
- Billing for network resources (LB forwarding rules, NAT) stays in the host project

## File structure

```
lab3-shared-vpc/
├── README.md
├── modules/
│   ├── shared-vpc/          # Host project network resources
│   │   ├── main.tf          # VPC, subnets, firewall, NAT
│   │   ├── variables.tf
│   │   └── outputs.tf
│   └── gke-service/         # GKE cluster in a service project
│       ├── main.tf          # Cluster using shared subnet
│       ├── iam.tf           # Node SA + Workload Identity
│       ├── variables.tf
│       └── outputs.tf
└── environments/
    └── lab/
        ├── host/            # Apply first — creates host project network
        │   ├── backend.tf
        │   ├── main.tf
        │   ├── variables.tf
        │   ├── outputs.tf
        │   └── terraform.tfvars
        ├── service-a/       # Apply second — GKE cluster
        │   ├── backend.tf
        │   ├── main.tf
        │   ├── variables.tf
        │   ├── outputs.tf
        │   └── terraform.tfvars
        └── service-b/       # Apply second — IAM binding only
            ├── backend.tf
            ├── main.tf
            ├── variables.tf
            └── terraform.tfvars
```

## Apply order — critical

Shared VPC has strict dependency ordering:
1. Host project Shared VPC must be enabled BEFORE service projects attach
2. Subnet IAM bindings must exist BEFORE GKE cluster creation
3. GKE cluster in service project references host project subnet self_links

```bash
# Step 1: Apply host project (creates VPC, enables Shared VPC, grants access)
cd environments/lab/host
terraform init -backend-config="bucket=YOUR_STATE_BUCKET"
terraform apply -var-file=terraform.tfvars

# Step 2: Apply service projects (reference host outputs via remote state)
cd ../service-a
terraform init -backend-config="bucket=YOUR_STATE_BUCKET"
terraform apply -var-file=terraform.tfvars

cd ../service-b
terraform init -backend-config="bucket=YOUR_STATE_BUCKET"
terraform apply -var-file=terraform.tfvars
```

## Verification

```bash
# Confirm Shared VPC is enabled on host project
gcloud compute shared-vpc get-host-project SERVICE_PROJECT_A_ID

# List subnets visible to service project A
gcloud compute networks subnets list-usable --project=SERVICE_PROJECT_A_ID

# Confirm service project A cannot see service project B's subnet
# (the above command should only show subnet-service-a)

# Confirm GKE cluster is running in service project A
gcloud container clusters list --project=SERVICE_PROJECT_A_ID

# Confirm nodes use the shared subnet
gcloud container clusters describe prod-cluster-a \
  --project=SERVICE_PROJECT_A_ID \
  --region=us-central1 \
  --format="yaml(networkConfig)"
```
