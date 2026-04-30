# modules/vpc/firewall.tf
#
# Firewall rule design principles used here:
#
# 1. TARGET TAGS not IP ranges for app-tier targeting.
#    "allow traffic to VMs tagged 'allow-web'" is more maintainable
#    than "allow traffic to 10.10.0.0/24" — IPs change, tags don't.
#
# 2. SOURCE SERVICE ACCOUNTS for service-to-service rules.
#    More secure than tags (tags can be self-applied by anyone with
#    compute.instances.setTags). Service accounts require IAM.
#    Shown in the allow-internal rule as a comment pattern.
#
# 3. EXPLICIT DENY at the end.
#    GCP has implicit deny-all at priority 65535. Making it explicit
#    at 65534 ensures it appears in audit logs and firewall listings.
#
# 4. PRIORITY GAPS between rules.
#    Rules use 1000, 2000, 3000... gaps so you can insert rules later
#    without renumbering. Never use consecutive priorities.
#
# 5. NO 0.0.0.0/0 ON PORT 22.
#    SSH access is IAP-only. IAP proxies connections from its own
#    range (35.235.240.0/20) so you never expose SSH publicly.
#
# Tag taxonomy used in this module:
#   allow-ssh        → VMs that accept SSH via IAP
#   allow-web        → VMs that accept HTTP/HTTPS from internet
#   allow-internal   → VMs that accept traffic from other VMs in VPC
#   allow-health-check → VMs behind load balancers

# ── IAP SSH ──────────────────────────────────────────────────────────────────
# Google Identity-Aware Proxy (IAP) allows SSH to private VMs without
# exposing port 22 to the internet. IAP establishes a WebSocket tunnel
# from the user's browser/gcloud to the VM via Google's infrastructure.
# The VM only sees connections from IAP's IP range: 35.235.240.0/20.

resource "google_compute_firewall" "allow_iap_ssh" {
  count = var.enable_iap_ssh ? 1 : 0

  name        = "${var.vpc_name}-allow-iap-ssh"
  project     = var.project_id
  network     = google_compute_network.vpc.id
  description = "Allow SSH from Google IAP to VMs tagged allow-ssh. Never allow 0.0.0.0/0 on port 22."
  direction   = "INGRESS"
  priority    = 1000

  # IAP's fixed IP range — this is Google-managed and does not change.
  # IAP validates user identity and IAM permissions before proxying.
  source_ranges = ["35.235.240.0/20"]

  # Only VMs with this tag receive this rule.
  # Apply the tag in your VM or instance template metadata.
  target_tags = ["allow-ssh"]

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  log_config {
    metadata = "INCLUDE_ALL_METADATA"
  }
}

# ── HTTP / HTTPS from internet ────────────────────────────────────────────────
# Allows public web traffic to VMs tagged 'allow-web'.
# In production, this rule typically targets a load balancer backend
# rather than VMs directly — but the tag pattern is the same.

resource "google_compute_firewall" "allow_http_https" {
  count = var.enable_http_https ? 1 : 0

  name        = "${var.vpc_name}-allow-http-https"
  project     = var.project_id
  network     = google_compute_network.vpc.id
  description = "Allow HTTP and HTTPS ingress from internet to VMs tagged allow-web."
  direction   = "INGRESS"
  priority    = 1000

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["allow-web"]

  allow {
    protocol = "tcp"
    ports    = ["80", "443"]
  }

  log_config {
    metadata = "INCLUDE_ALL_METADATA"
  }
}

# ── Internal VPC traffic ──────────────────────────────────────────────────────
# Allows VMs to talk to each other within the VPC on all protocols.
# Source ranges should cover all subnet primary CIDRs in this VPC.
# Target tag 'allow-internal' controls which VMs accept this traffic.
#
# Production refinement: replace this broad rule with narrower rules:
#   web tier → app tier (port 8080)
#   app tier → db tier (port 5432)
# Use source_tags or source_service_accounts for app-tier targeting.

resource "google_compute_firewall" "allow_internal" {
  count = length(var.internal_source_ranges) > 0 ? 1 : 0

  name        = "${var.vpc_name}-allow-internal"
  project     = var.project_id
  network     = google_compute_network.vpc.id
  description = "Allow all traffic between VMs within internal CIDR ranges. Tag VMs with allow-internal to receive this rule."
  direction   = "INGRESS"
  priority    = 2000

  source_ranges = var.internal_source_ranges
  target_tags   = ["allow-internal"]

  allow {
    protocol = "tcp"
    ports    = ["0-65535"]
  }

  allow {
    protocol = "udp"
    ports    = ["0-65535"]
  }

  allow {
    protocol = "icmp"
  }

  log_config {
    metadata = "INCLUDE_ALL_METADATA"
  }
}

# ── GCP Load Balancer health checks ──────────────────────────────────────────
# REQUIRED for any VM behind an HTTP(S), TCP, or SSL Load Balancer.
# GCP LB health checks originate from two fixed ranges.
# Without this rule, health checks silently fail and backends are
# marked unhealthy — one of the most common LB bring-up failures.
#
# These ranges are Google-managed and documented at:
# https://cloud.google.com/load-balancing/docs/health-checks#firewall_rules

resource "google_compute_firewall" "allow_health_checks" {
  name        = "${var.vpc_name}-allow-health-checks"
  project     = var.project_id
  network     = google_compute_network.vpc.id
  description = "Allow GCP load balancer health check probes. Required for all LB backends. Without this, backends are always unhealthy."
  direction   = "INGRESS"
  priority    = 3000

  # These two ranges are Google's health checker source IPs.
  # They do not change — safe to hardcode.
  source_ranges = [
    "35.191.0.0/16",   # Global LB health checks
    "130.211.0.0/22",  # Legacy and regional LB health checks
  ]

  target_tags = ["allow-health-check"]

  allow {
    protocol = "tcp"
    # Allow on all ports — health checker uses the port configured
    # on the backend service, which varies per workload.
  }

  log_config {
    metadata = "INCLUDE_ALL_METADATA"
  }
}

# ── Explicit deny-all ingress ─────────────────────────────────────────────────
# GCP has an implicit deny-all ingress at priority 65535.
# This explicit rule at 65534 serves two purposes:
#   1. Appears in firewall rule listings (visible to auditors)
#   2. Generates Cloud Firewall log entries for denied traffic
#      (the implicit deny does NOT log — this one does with log_config)
#
# This rule applies to ALL VMs regardless of tags.
# All higher-priority ALLOW rules take precedence.

resource "google_compute_firewall" "deny_all_ingress" {
  count = var.enable_deny_all_ingress ? 1 : 0

  name        = "${var.vpc_name}-deny-all-ingress"
  project     = var.project_id
  network     = google_compute_network.vpc.id
  description = "Explicit deny-all ingress at priority 65534. Makes the implicit deny visible in audit logs and firewall listings. All allow rules above this have higher priority."
  direction   = "INGRESS"

  # Priority 65534 — just above GCP's implicit deny at 65535.
  # All allow rules in this module use priorities 1000-3000,
  # so they always take precedence.
  priority = 65534

  source_ranges = ["0.0.0.0/0"]

  deny {
    protocol = "all"
  }

  # IMPORTANT: log_config on a deny rule generates an audit trail
  # of all traffic that hit no allow rule. Useful for security
  # investigations and compliance. Can be high volume — filter
  # in Cloud Logging if cost is a concern.
  log_config {
    metadata = "INCLUDE_ALL_METADATA"
  }
}

# ── Egress allow-all (default) ────────────────────────────────────────────────
# GCP allows all egress by default (implicit allow at priority 65535).
# We make this explicit here so it appears in audit listings.
# To restrict egress (e.g. force all traffic through a proxy),
# delete this rule and add specific egress allow rules instead.

resource "google_compute_firewall" "allow_all_egress" {
  name        = "${var.vpc_name}-allow-all-egress"
  project     = var.project_id
  network     = google_compute_network.vpc.id
  description = "Explicit allow-all egress. GCP has this implicitly at 65535 — making it explicit for audit visibility. Replace with specific egress rules if egress filtering is required."
  direction   = "EGRESS"
  priority    = 65534

  destination_ranges = ["0.0.0.0/0"]

  allow {
    protocol = "all"
  }
}
