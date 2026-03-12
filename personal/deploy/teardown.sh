#!/usr/bin/env bash
# teardown.sh — Destroy all Oracle Cloud resources created by deploy.sh
#
# Usage: ./teardown.sh
#
# Reads .deploy-state for resource IDs. Destroys in reverse order:
#   instance → subnet → internet gateway → VCN

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
STATE_FILE="$SCRIPT_DIR/.deploy-state"

if [ ! -f "$STATE_FILE" ]; then
  echo "ERROR: No .deploy-state file found. Nothing to tear down."
  echo "If resources exist, delete them manually in the OCI console."
  exit 1
fi

source "$STATE_FILE"
source "$SCRIPT_DIR/config.env"

echo "=== Oracle Cloud Teardown ==="
echo "This will DESTROY all resources:"
echo "  Instance: $INSTANCE_ID"
echo "  Subnet:   $SUBNET_ID"
echo "  IGW:      $IGW_ID"
echo "  VCN:      $VCN_ID"
echo ""
read -rp "Type 'destroy' to confirm: " CONFIRM
if [ "$CONFIRM" != "destroy" ]; then
  echo "Aborted."
  exit 0
fi

echo ""

# --- Terminate instance ---
echo "→ Terminating instance..."
oci compute instance terminate \
  --instance-id "$INSTANCE_ID" \
  --preserve-boot-volume false \
  --force \
  --wait-for-state TERMINATED >/dev/null 2>&1
echo "  Instance terminated"

# --- Delete subnet ---
echo "→ Deleting subnet..."
oci network subnet delete \
  --subnet-id "$SUBNET_ID" \
  --force \
  --wait-for-state TERMINATED >/dev/null 2>&1
echo "  Subnet deleted"

# --- Delete internet gateway ---
echo "→ Deleting internet gateway..."
# Clear route table first (IGW can't be deleted while referenced)
RT_ID=$(oci network route-table list \
  --compartment-id "$COMPARTMENT_OCID" \
  --vcn-id "$VCN_ID" \
  --query 'data[0].id' --raw-output)

oci network route-table update \
  --rt-id "$RT_ID" \
  --route-rules '[]' \
  --force \
  --wait-for-state AVAILABLE >/dev/null 2>&1

oci network internet-gateway delete \
  --ig-id "$IGW_ID" \
  --force \
  --wait-for-state TERMINATED >/dev/null 2>&1
echo "  Internet gateway deleted"

# --- Delete VCN ---
echo "→ Deleting VCN..."
oci network vcn delete \
  --vcn-id "$VCN_ID" \
  --force \
  --wait-for-state TERMINATED >/dev/null 2>&1
echo "  VCN deleted"

# --- Cleanup state ---
rm -f "$STATE_FILE"
echo ""
echo "=== Teardown Complete ==="
echo "All resources destroyed. State file removed."
