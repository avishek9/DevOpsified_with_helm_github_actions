# environments/lab/projects/terraform.tfvars

billing_account_id = "XXXXXX-XXXXXX-XXXXXX"  # gcloud billing accounts list

# Choose ONE of the following placement options:

# Option A: personal GCP account (no org, no folder)
org_id    = null
folder_id = null

# Option B: GCP org, projects directly under org root
# org_id    = "123456789012"   # gcloud organizations list
# folder_id = null

# Option C: GCP org, projects under a specific folder (recommended)
# org_id    = null
# folder_id = "folders/987654321098"

# Prefix for project IDs — must be globally unique
# Full IDs become: PREFIX-host, PREFIX-svc-a, PREFIX-svc-b
project_id_prefix = "yourname-lab3"  # e.g. "jsmith-lab3"
