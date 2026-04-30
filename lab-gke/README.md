# Lab — Production GKE Standard Cluster

## What this builds

**Cluster:**
- Regional (control plane in 3 zones — survives a single zone failure)
- Standard mode (platform engineers manage node pools)
- Private nodes (no external IPs on VMs)
- Private or restricted control plane endpoint
- REGULAR release channel with weekend maintenance window
- Dataplane V2 (eBPF, native NetworkPolicy)
- Cloud DNS for cluster DNS
- VPC-native networking (alias IPs, required for private clusters)
- Workload Identity enabled
- Binary Authorization enforcing
- Shielded nodes (Secure Boot + vTPM + Integrity Monitoring)
- Managed Prometheus enabled
- Full audit logging (API server, workloads, system components)

**Node pools:**

| Pool    | Type         | Count            | Taint                              | Use case                      |
|---------|------------- |------------------|------------------------------------|-------------------------------|
| system  | On-demand    | 1/zone (fixed)   | CriticalAddonsOnly=true:NoSchedule | CoreDNS, kube-proxy, addons   |
| general | On-demand    | 1–10/zone (auto) | None                               | Stateless application workloads |
| spot    | Spot VM      | 0–5/zone (auto)  | cloud.google.com/gke-spot:NoSchedule | Batch jobs, interruptible work |

**IAM:**
- Dedicated node SA with minimum permissions (log writer, metric writer, AR reader)
- Binary Authorization policy with GKE system image whitelist
- Workload Identity binding example for `my-service`

## File structure

```
lab-gke/
├── modules/
│   └── gke/
│       ├── main.tf       # Cluster + node pools
│       ├── iam.tf        # Node SA + Binary Authorization policy
│       ├── variables.tf  # All module inputs with validation
│       └── outputs.tf    # Cluster name, endpoint, WI pool
└── environments/
    └── prod/
        ├── backend.tf        # GCS remote state
        ├── variables.tf      # Environment inputs
        ├── main.tf           # Calls module, adds workload bindings
        ├── outputs.tf        # Verification commands
        └── terraform.tfvars  # Actual values (gitignore in real repos)
```

## Prerequisites

```bash
# 1. Enable APIs
gcloud services enable \
  container.googleapis.com \
  binaryauthorization.googleapis.com \
  artifactregistry.googleapis.com \
  --project=YOUR_PROJECT_ID

# 2. Apply lab1-vpc first (cluster needs VPC + subnets with secondary ranges)
cd ../lab1-vpc/environments/dev
terraform apply

# 3. Note the subnet and range names from lab1-vpc outputs
terraform output subnets
```

## Apply sequence

```bash
cd environments/prod

# Edit terraform.tfvars with your values
vim terraform.tfvars

# Initialise
terraform init -backend-config="bucket=your-state-bucket"

# Preview
terraform plan -var-file=terraform.tfvars

# Apply — takes ~15 minutes for a new regional cluster
terraform apply -var-file=terraform.tfvars

# Configure kubectl
$(terraform output -raw get_credentials_command)

# Run verification
kubectl get nodes -o wide
```

## Known first-apply issue: node SA self-reference

`main.tf` passes `module.gke.node_service_account_email` back into the
module call, which creates a dependency cycle on the first apply.

**Fix for first apply:**
```bash
# Apply only the SA first
terraform apply -target=module.gke.google_service_account.node_sa

# Then apply everything else
terraform apply
```

Alternatively, create the node SA outside the module and pass its email
as a static variable in `terraform.tfvars`.

## Binary Authorization migration path

The policy starts with an empty `require_attestations_by = []` list,
which means BinAuthz is enforcing but requires zero attestations — all
images pass. This is intentional for the initial rollout.

To add real enforcement:
1. Create a Cloud Build attestor: `gcloud container binauthz attestors create`
2. Configure Cloud Build to sign images after security scans pass
3. Add the attestor URI to `require_attestations_by` in `iam.tf`
4. Test in AUDIT_LOG_ONLY mode before switching to ENFORCED_BLOCK

## Workload Identity setup per application

After cluster creation, for each application workload:

```bash
# 1. Create GCP SA (done in main.tf for my-service — repeat per workload)

# 2. Apply the IAM binding (done in main.tf)

# 3. Create the Kubernetes SA with annotation (in your Helm chart or directly)
kubectl create serviceaccount my-service-ksa -n production
kubectl annotate serviceaccount my-service-ksa -n production \
  iam.gke.io/gcp-service-account=$(terraform output -raw my_service_gcp_sa_email)

# 4. Verify Workload Identity works
kubectl run wi-test --image=google/cloud-sdk:slim \
  --serviceaccount=my-service-ksa -n production \
  --rm -it --restart=Never \
  -- gcloud auth print-access-token
```
