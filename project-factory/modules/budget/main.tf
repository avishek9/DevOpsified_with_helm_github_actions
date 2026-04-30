# modules/budget/main.tf
#
# Creates a budget alert for the project.
# Budget alerts do NOT stop spending — they notify.
# For hard spending caps, use org policy constraints instead.
#
# Migration context: budget alerts are critical during migration
# because teams often underestimate GCP costs when replicating
# on-prem workloads that had amortised hardware costs.

terraform {
  required_providers {
    google = { source = "hashicorp/google"
    version = ">= 5.0, < 6.0" }
  }
}

variable "entry"              { type = any }
variable "project_id"         { type = string }
variable "billing_account_id" { type = string }

resource "google_billing_budget" "budget" {
  billing_account = var.billing_account_id
  display_name    = "Budget — ${var.entry.project.team} ${var.entry.project.environment}"

  budget_filter {
    projects = ["projects/${var.project_id}"]
    # credit_types_treatment: INCLUDE_ALL_CREDITS accounts for
    # committed use discount credits — use EXCLUDE_ALL_CREDITS
    # if you want alerts based on list price spend
    credit_types_treatment = "INCLUDE_ALL_CREDITS"
  }

  amount {
    specified_amount {
      currency_code = "USD"
      units         = tostring(var.entry.budget.monthly_limit_usd)
    }
  }

  # Create one threshold rule per alert percentage in the registry
  dynamic "threshold_rules" {
    for_each = try(var.entry.budget.alert_thresholds, [50, 80, 100])
    content {
      threshold_percent = threshold_rules.value / 100
      spend_basis       = "CURRENT_SPEND"
    }
  }

  # Email notifications to all addresses in the registry entry
  all_updates_rule {
    monitoring_notification_channels = []
    # Pub/Sub topic for programmatic alerting (e.g. auto-scaling down)
    # disable_default_iam_recipients = false means billing account
    # admins also receive alerts regardless of this config
    disable_default_iam_recipients = false
  }
}
