#!/bin/bash
# verify.sh — run after terraform apply to confirm everything is correct
#
# Usage:
#   chmod +x verify.sh
#   ./verify.sh YOUR_PROJECT_ID lab1-vpc-dev

set -euo pipefail

PROJECT_ID="${1:?Usage: ./verify.sh PROJECT_ID VPC_NAME}"
VPC_NAME="${2:?Usage: ./verify.sh PROJECT_ID VPC_NAME}"

echo ""
echo "======================================================"
echo "  Lab 1 VPC verification: $VPC_NAME"
echo "======================================================"

# ── 1. VPC exists and is custom mode ─────────────────────────────────────────
echo ""
echo "▶ 1. VPC network"
gcloud compute networks describe "$VPC_NAME" \
  --project="$PROJECT_ID" \
  --format="table(name,autoCreateSubnetworks,routingConfig.routingMode)"

echo ""
echo "  PASS if: autoCreateSubnetworks = False, routingMode = GLOBAL"

# ── 2. Subnets with Private Google Access ─────────────────────────────────────
echo ""
echo "▶ 2. Subnets with Private Google Access"
gcloud compute networks subnets list \
  --project="$PROJECT_ID" \
  --filter="network=$VPC_NAME" \
  --format="table(name,region,ipCidrRange,privateIpGoogleAccess)"

echo ""
echo "  PASS if: privateIpGoogleAccess = True on all subnets"

# ── 3. Secondary ranges ───────────────────────────────────────────────────────
echo ""
echo "▶ 3. Secondary ranges (pods + services per subnet)"
gcloud compute networks subnets list \
  --project="$PROJECT_ID" \
  --filter="network=$VPC_NAME" \
  --format="yaml(name,secondaryIpRanges)"

echo ""
echo "  PASS if: each subnet has two secondary ranges (-pods and -services)"

# ── 4. Firewall rules ─────────────────────────────────────────────────────────
echo ""
echo "▶ 4. Firewall rules"
gcloud compute firewall-rules list \
  --project="$PROJECT_ID" \
  --filter="network=$VPC_NAME" \
  --format="table(name,direction,priority,sourceRanges,targetTags,denied[].protocol,allowed[].protocol,allowed[].ports)"

echo ""
echo "  PASS if:"
echo "    - allow-iap-ssh:      source=35.235.240.0/20,  target=allow-ssh,         port=22"
echo "    - allow-http-https:   source=0.0.0.0/0,         target=allow-web,         ports=80,443"
echo "    - allow-internal:     source=10.x.x.x ranges,  target=allow-internal,    all ports"
echo "    - allow-health-checks: source=35.191.0.0/16,   target=allow-health-check"
echo "    - deny-all-ingress:   source=0.0.0.0/0,         no target tag,            deny all"
echo "    - NO rule allows 0.0.0.0/0 on port 22"

# ── 5. Cloud Router and NAT ───────────────────────────────────────────────────
echo ""
echo "▶ 5. Cloud Routers and NAT gateways"
gcloud compute routers list \
  --project="$PROJECT_ID" \
  --filter="network=$VPC_NAME" \
  --format="table(name,region,network)"

echo ""
echo "  PASS if: one router per region (us-central1, europe-west1)"

# ── 6. Private Google Access functional test ─────────────────────────────────
echo ""
echo "▶ 6. Private Google Access test"
echo "   To test PGA, deploy a VM without an external IP and run:"
echo ""
echo "   gcloud compute instances create test-pga-vm \\"
echo "     --project=$PROJECT_ID \\"
echo "     --zone=us-central1-a \\"
echo "     --machine-type=e2-micro \\"
echo "     --subnet=subnet-us-central1-dev \\"
echo "     --no-address \\"
echo "     --metadata=startup-script='curl -s https://storage.googleapis.com/ > /tmp/pga-test.txt'"
echo ""
echo "   Then check:"
echo "   gcloud compute ssh test-pga-vm --tunnel-through-iap --zone=us-central1-a \\"
echo "     -- cat /tmp/pga-test.txt"
echo ""
echo "   PASS if: response contains XML (not a connection error)"
echo ""
echo "   Don't forget to delete the test VM:"
echo "   gcloud compute instances delete test-pga-vm --zone=us-central1-a --project=$PROJECT_ID"

echo ""
echo "======================================================"
echo "  Verification complete"
echo "======================================================"
