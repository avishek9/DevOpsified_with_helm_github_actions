#!/usr/bin/env python3
# pipeline/scripts/validate_registry.py
#
# Validates every YAML file in registry/projects/ against the schema.
# Runs in CI before terraform plan — catches mistakes before they hit GCP.
#
# Checks:
#   - Required fields present
#   - Project ID format (GCP naming rules)
#   - No duplicate project IDs across registry
#   - No overlapping subnet CIDRs
#   - Budget limit sanity (> 0, not absurdly high without approval flag)
#   - IAM members are valid format (user:, group:, serviceAccount:)
#
# Usage: python3 validate_registry.py
# Exit 0 = valid, Exit 1 = validation errors found

import os
import sys
import yaml
import re
import ipaddress
from pathlib import Path

REGISTRY_DIR = Path(__file__).parent.parent.parent / "registry" / "projects"
ERRORS = []

def error(file, msg):
    ERRORS.append(f"  [{file}] {msg}")

def validate_project_id(project_id, filename):
    """GCP project ID rules: 6-30 chars, lowercase letters/numbers/hyphens,
    must start with letter, cannot end with hyphen."""
    pattern = r'^[a-z][a-z0-9\-]{4,28}[a-z0-9]$'
    if not re.match(pattern, project_id):
        error(filename, f"project.id '{project_id}' violates GCP naming rules "
              f"(6-30 chars, lowercase, start with letter, no trailing hyphen)")

def validate_cidr(cidr, field, filename):
    """Validate CIDR block format."""
    try:
        ipaddress.ip_network(cidr, strict=True)
    except ValueError:
        error(filename, f"{field} '{cidr}' is not a valid CIDR block")

def validate_iam_member(member, filename):
    """IAM member must have a valid prefix."""
    valid_prefixes = ["user:", "group:", "serviceAccount:", "domain:"]
    if not any(member.startswith(p) for p in valid_prefixes):
        error(filename, f"IAM member '{member}' must start with one of: "
              f"{', '.join(valid_prefixes)}")

def validate_entry(entry, filename):
    """Validate a single registry entry."""
    # Required top-level sections
    for section in ["project", "networking", "iam", "budget"]:
        if section not in entry:
            error(filename, f"Missing required section: '{section}'")
            return  # cannot validate further without required sections

    proj = entry["project"]

    # Required project fields
    for field in ["id", "name", "environment", "team", "cost_center"]:
        if field not in proj:
            error(filename, f"Missing required field: project.{field}")

    if "id" in proj:
        validate_project_id(proj["id"], filename)

    if "environment" in proj:
        if proj["environment"] not in ["dev", "staging", "prod"]:
            error(filename, f"project.environment must be dev, staging, or prod")

    if "cost_center" in proj:
        if not re.match(r'^CC-\d{4}$', proj["cost_center"]):
            error(filename, f"project.cost_center must match CC-XXXX format")

    # Networking validation
    net = entry.get("networking", {})
    for cidr_field in ["subnet_cidr", "pods_cidr", "services_cidr"]:
        if cidr_field in net:
            validate_cidr(net[cidr_field], f"networking.{cidr_field}", filename)

    if "subnet_cidr" not in net:
        error(filename, "networking.subnet_cidr is required")

    # IAM validation
    iam = entry.get("iam", {})
    for role in ["owners", "editors", "viewers"]:
        for member in iam.get(role, []):
            validate_iam_member(member, filename)

    # Budget validation
    budget = entry.get("budget", {})
    if "monthly_limit_usd" not in budget:
        error(filename, "budget.monthly_limit_usd is required")
    elif budget["monthly_limit_usd"] <= 0:
        error(filename, "budget.monthly_limit_usd must be > 0")
    elif budget["monthly_limit_usd"] > 50000:
        # Large budgets need an explicit approval flag to catch mistakes
        if not budget.get("large_budget_approved", False):
            error(filename, f"budget.monthly_limit_usd > $50,000 requires "
                  f"large_budget_approved: true (get FinOps approval)")

    if "alert_emails" not in budget or not budget["alert_emails"]:
        error(filename, "budget.alert_emails must contain at least one address")

def check_duplicate_project_ids(entries):
    """No two registry entries can have the same project ID."""
    seen = {}
    for filename, entry in entries.items():
        pid = entry.get("project", {}).get("id")
        if pid:
            if pid in seen:
                error(filename, f"Duplicate project.id '{pid}' — "
                      f"already used in {seen[pid]}")
            else:
                seen[pid] = filename

def check_overlapping_cidrs(entries):
    """No two registry entries can have overlapping subnet CIDRs."""
    seen_cidrs = {}
    for filename, entry in entries.items():
        cidr = entry.get("networking", {}).get("subnet_cidr")
        if cidr:
            try:
                net = ipaddress.ip_network(cidr, strict=True)
                for existing_cidr, existing_file in seen_cidrs.items():
                    existing_net = ipaddress.ip_network(existing_cidr, strict=True)
                    if net.overlaps(existing_net):
                        error(filename, f"networking.subnet_cidr '{cidr}' overlaps "
                              f"with '{existing_cidr}' in {existing_file}")
                seen_cidrs[cidr] = filename
            except ValueError:
                pass  # already caught by validate_cidr

def main():
    if not REGISTRY_DIR.exists():
        print(f"ERROR: Registry directory not found: {REGISTRY_DIR}")
        sys.exit(1)

    yaml_files = list(REGISTRY_DIR.glob("*.yaml"))
    if not yaml_files:
        print("WARNING: No registry entries found in registry/projects/")
        sys.exit(0)

    entries = {}
    for path in yaml_files:
        filename = path.name
        try:
            with open(path) as f:
                entry = yaml.safe_load(f)
            if entry is None:
                error(filename, "File is empty or contains no valid YAML")
                continue
            entries[filename] = entry
            validate_entry(entry, filename)
        except yaml.YAMLError as e:
            error(filename, f"YAML parse error: {e}")

    # Cross-entry validations
    check_duplicate_project_ids(entries)
    check_overlapping_cidrs(entries)

    if ERRORS:
        print(f"\nRegistry validation FAILED — {len(ERRORS)} error(s):\n")
        for e in ERRORS:
            print(e)
        print(f"\nFix these errors before re-running terraform plan.\n")
        sys.exit(1)
    else:
        print(f"Registry validation PASSED — {len(entries)} entries valid.")
        sys.exit(0)

if __name__ == "__main__":
    main()
