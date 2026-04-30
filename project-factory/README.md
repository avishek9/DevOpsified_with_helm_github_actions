# GCP Project Factory — Migration Scale

## What this solves

Without a factory: onboarding a new team during migration =
  1. Team raises a Jira ticket to the platform team
  2. Platform engineer writes Terraform in the monorepo
  3. PR review, approval, apply
  4. 3-5 days per team, platform team is a bottleneck

With a factory: onboarding a new team =
  1. Team adds one YAML entry to registry/projects/
  2. PR review by platform team (governance check only)
  3. Pipeline runs automatically on merge
  4. Team has a fully provisioned GCP environment in ~15 minutes

At migration scale (40+ workloads), the factory is the difference
between a 6-month migration and a 2-year migration.

## Architecture

```
project-factory/
├── registry/                    # Teams own this — YAML entries only
│   ├── _schema.yaml             # Validation schema for entries
│   └── projects/
│       ├── team-payments.yaml   # One file per team/workload
│       ├── team-analytics.yaml
│       └── team-identity.yaml
│
├── modules/                     # Platform team owns this — never edited by teams
│   ├── project/                 # GCP project + billing + APIs
│   ├── networking/              # Shared VPC subnet + NCC spoke
│   ├── iam/                     # Team IAM bindings + Workload Identity
│   └── budget/                  # Budget alerts + cost attribution
│
├── factory/                     # The glue — reads registry, calls modules
│   ├── main.tf                  # yamldecode() + for_each over all entries
│   ├── variables.tf             # Billing account, org, host project
│   ├── outputs.tf
│   └── backend.tf
│
└── pipeline/                    # CI/CD — GitLab CI or GitHub Actions
    ├── .gitlab-ci.yml
    └── scripts/
        ├── validate_registry.py  # Schema validation before plan
        └── notify_team.sh        # Slack notification on apply
```

## Registry entry anatomy

Each YAML file in registry/projects/ defines one team's GCP environment:

```yaml
# registry/projects/team-payments.yaml
project:
  id: acme-payments-prod           # globally unique, immutable
  name: "Payments Team — Production"
  environment: prod                # dev | staging | prod
  team: payments
  cost_center: "CC-1234"

networking:
  subnet_cidr: "10.50.0.0/20"
  pods_cidr: "10.150.0.0/18"
  services_cidr: "10.250.0.0/22"
  connect_to_onprem: true          # adds NCC spoke for hybrid connectivity
  shared_vpc: true                 # attach to host project Shared VPC

iam:
  owners:
    - user:alice@acme.com
    - group:payments-leads@acme.com
  editors:
    - group:payments-engineers@acme.com
  viewers:
    - group:security-audit@acme.com

gke:
  enabled: true
  node_pool_size: "small"          # small | medium | large (maps to machine types)
  release_channel: REGULAR

budget:
  monthly_limit_usd: 5000
  alert_thresholds: [50, 80, 100]
  alert_emails:
    - payments-leads@acme.com
    - finops@acme.com
```

## Migration workflow

During a cloud migration, each on-prem workload gets a registry entry:

1. Migration assessment produces a workload inventory
2. Each workload maps to one registry entry
3. Platform team reviews and merges in batches
4. Pipeline provisions GCP environments automatically
5. App teams deploy their workloads into the provisioned environment

NCC integration: if connect_to_onprem: true, the factory creates an NCC
spoke connecting this project's VPC to the hub, giving the workload
access to on-prem systems during the migration transition period.
The spoke is removed from the registry entry once migration is complete.

## Apply order

The factory has two Terraform roots — both must be applied in order:

1. factory/foundation/   — org-level: billing, host project, NCC hub
2. factory/             — per-project: reads registry, creates everything
```
