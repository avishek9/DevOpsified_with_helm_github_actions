# Project Factory — Hands-on Exercises

## Exercise 1: Onboard a new team (the baseline operation)

Goal: understand what "adding a project" looks like end-to-end.

```bash
# 1. Copy the template entry
cp registry/projects/team-identity-dev.yaml \
   registry/projects/team-orders-prod.yaml

# 2. Edit the new entry
#    - Change project.id to a unique value (e.g. yourname-orders-prod)
#    - Change project.team to "orders"
#    - Change networking.subnet_cidr to 10.80.0.0/20
#    - Change pods_cidr to 10.180.0.0/18
#    - Change services_cidr to 10.280.0.0/22
#    - Set connect_to_onprem: false

# 3. Validate before planning
python3 pipeline/scripts/validate_registry.py
# Should pass with 4 entries

# 4. Plan — observe what Terraform intends to create
cd factory
terraform init -backend-config="bucket=YOUR_STATE_BUCKET"
terraform plan -var-file=terraform.tfvars

# Observe: plan shows new module.project["team-orders-prod"],
# module.networking["team-orders-prod"], etc.
# All other projects are untouched — plan is scoped to the new entry.

# 5. Apply
terraform apply -var-file=terraform.tfvars

# 6. Verify project exists
gcloud projects describe yourname-orders-prod

# 7. Check the factory output inventory
terraform output project_inventory
```

---

## Exercise 2: Simulate migration onboarding (connect_to_onprem flow)

Goal: understand the NCC spoke lifecycle during a migration.

```bash
# 1. Edit team-payments.yaml — simulate it being onboarded for migration
#    Confirm connect_to_onprem: true is set

# 2. Plan and apply
terraform plan -var-file=terraform.tfvars
terraform apply -var-file=terraform.tfvars

# 3. Check migration status output
terraform output migration_status
# Should show team-payments as migrating

# 4. Verify NCC spoke was created
gcloud network-connectivity spokes list \
  --hub=migration-hub \
  --project=YOUR_HOST_PROJECT

# 5. Simulate migration complete — remove on-prem dependency
#    Edit registry/projects/team-payments.yaml:
#    Change connect_to_onprem: true → connect_to_onprem: false

# 6. Plan — observe spoke destruction
terraform plan -var-file=terraform.tfvars
# Plan should show only the NCC spoke being destroyed.
# Project, subnet, IAM bindings are unchanged.

# 7. Apply
terraform apply -var-file=terraform.tfvars

# 8. Verify spoke is gone
terraform output migration_status
# team-payments should no longer appear
```

---

## Exercise 3: Validate the schema catches bad entries

Goal: understand why the validation step exists and what it catches.

```bash
# 1. Create a deliberately invalid entry
cat > registry/projects/bad-entry.yaml << 'EOF'
project:
  id: BAD_ID_WITH_CAPS    # invalid: uppercase not allowed
  name: "Bad Entry"
  environment: unknown    # invalid: not in [dev, staging, prod]
  # team: missing         # missing required field
  cost_center: "1234"     # invalid: must be CC-XXXX

networking:
  subnet_cidr: "10.50.0.0/20"  # overlaps with team-payments!

iam:
  owners:
    - alice@acme.com      # invalid: missing user: prefix

budget:
  monthly_limit_usd: -100  # invalid: must be > 0
  alert_emails: []          # invalid: at least one required
EOF

# 2. Run validation — should fail with multiple errors
python3 pipeline/scripts/validate_registry.py

# Expected output:
# Registry validation FAILED — 7 error(s):
#   [bad-entry.yaml] project.id 'BAD_ID_WITH_CAPS' violates GCP naming rules
#   [bad-entry.yaml] project.environment must be dev, staging, or prod
#   [bad-entry.yaml] Missing required field: project.team
#   [bad-entry.yaml] project.cost_center must match CC-XXXX format
#   [bad-entry.yaml] IAM member 'alice@acme.com' must start with one of: user:, group:...
#   [bad-entry.yaml] budget.monthly_limit_usd must be > 0
#   [bad-entry.yaml] budget.alert_emails must contain at least one address
#   [bad-entry.yaml] networking.subnet_cidr '10.50.0.0/20' overlaps with...

# 3. Remove the bad entry
rm registry/projects/bad-entry.yaml

# 4. Confirm validation passes again
python3 pipeline/scripts/validate_registry.py
```

---

## Exercise 4: Targeted apply — only one project

Goal: in production with 50+ projects, you don't want a full plan/apply
to touch everything when you're only changing one registry entry.

```bash
# Terraform targets let you scope plan/apply to specific module instances.
# The module key is the registry filename stem (without .yaml).

# Plan only for the payments team
terraform plan \
  -var-file=terraform.tfvars \
  -target='module.project["team-payments"]' \
  -target='module.networking["team-payments"]' \
  -target='module.iam["team-payments"]' \
  -target='module.budget["team-payments"]'

# Apply only for the payments team
terraform apply \
  -var-file=terraform.tfvars \
  -target='module.project["team-payments"]' \
  -target='module.networking["team-payments"]' \
  -target='module.iam["team-payments"]' \
  -target='module.budget["team-payments"]'

# Note: -target is a tactical tool, not a workflow.
# In the GitLab CI pipeline, full applies are preferred because
# Terraform's dependency graph handles ordering correctly.
# Use -target only for emergency hotfixes or initial bootstrapping.
```

---

## Exercise 5: Interview simulation

These are the exact questions a JD2-level interviewer would ask.
Answer them with reference to the code you just built.

Q1: "How do you onboard a new team during a cloud migration?"
-> Point to registry/projects/team-payments.yaml. One YAML file,
   one PR, one pipeline run. The platform team reviews governance
   (subnet CIDR, IAM members, budget) not Terraform mechanics.

Q2: "How do you manage the transition period when a workload
    still needs to talk to on-prem systems?"
-> connect_to_onprem: true creates an NCC spoke connecting the
   project's VPC to the migration hub. The hub has an Interconnect
   or VPN to on-prem. The spoke is removed by flipping the flag
   to false and re-applying — no manual NCC cleanup needed.

Q3: "What prevents a team from giving themselves owner on a
    project they shouldn't have access to?"
-> The registry PR requires platform team review. The validate_registry.py
   script catches malformed member formats. In a mature setup, add an
   OPA/Conftest policy check in CI that rejects certain principals
   (e.g. external email domains, service accounts from other projects).

Q4: "How do you handle 50 projects without Terraform state getting
    unmanageable?"
-> Single state file, for_each over the registry. Terraform plans
   changes to only the entries that changed. A new YAML file adds
   exactly the resources for that entry and nothing else. State file
   size scales linearly but remains a single file with clear structure.

Q5: "What happens if you delete a YAML entry?"
-> Terraform plans to destroy all resources for that entry — project,
   subnet IAM bindings, NCC spoke, budget. The CI pipeline catches this
   because the plan check fails if any destroys are present (unless
   TF_ALLOW_DESTROY=true is set). Project deletion is additionally
   protected by prevent_destroy = true on the google_project resource —
   it requires a two-step process: remove the lifecycle block, re-apply,
   then delete. This prevents accidental project destruction.
```
