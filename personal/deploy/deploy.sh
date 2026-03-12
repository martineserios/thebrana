#!/usr/bin/env bash
# deploy.sh — Provision Oracle Cloud Free Tier ARM instance for personal bot
#
# Prerequisites:
#   1. OCI CLI installed and configured (`oci setup config`)
#   2. config.env filled in (copy from config.env.example)
#
# Usage: ./deploy.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/config.env"

# --- Defaults ---
DISPLAY_NAME="${DISPLAY_NAME:-personal-bot}"
VCN_CIDR="10.0.0.0/16"
SUBNET_CIDR="10.0.0.0/24"
SHAPE="VM.Standard.A1.Flex"
OCPUS="${OCPUS:-1}"
MEMORY_GB="${MEMORY_GB:-6}"

echo "=== Oracle Cloud Free Tier Deploy ==="
echo "Region:      $OCI_REGION"
echo "Compartment: $COMPARTMENT_OCID"
echo "Shape:       $SHAPE ($OCPUS OCPU, ${MEMORY_GB}GB)"
echo ""

# --- Availability Domain ---
echo "→ Finding availability domain..."
AD=$(oci iam availability-domain list \
  --compartment-id "$COMPARTMENT_OCID" \
  --query 'data[0].name' --raw-output)
echo "  AD: $AD"

# --- VCN ---
echo "→ Creating VCN..."
VCN_ID=$(oci network vcn create \
  --compartment-id "$COMPARTMENT_OCID" \
  --cidr-block "$VCN_CIDR" \
  --display-name "${DISPLAY_NAME}-vcn" \
  --query 'data.id' --raw-output \
  --wait-for-state AVAILABLE 2>/dev/null || \
  oci network vcn list \
    --compartment-id "$COMPARTMENT_OCID" \
    --display-name "${DISPLAY_NAME}-vcn" \
    --query 'data[0].id' --raw-output)
echo "  VCN: $VCN_ID"

# --- Internet Gateway ---
echo "→ Creating Internet Gateway..."
IGW_ID=$(oci network internet-gateway create \
  --compartment-id "$COMPARTMENT_OCID" \
  --vcn-id "$VCN_ID" \
  --is-enabled true \
  --display-name "${DISPLAY_NAME}-igw" \
  --query 'data.id' --raw-output \
  --wait-for-state AVAILABLE 2>/dev/null || \
  oci network internet-gateway list \
    --compartment-id "$COMPARTMENT_OCID" \
    --vcn-id "$VCN_ID" \
    --display-name "${DISPLAY_NAME}-igw" \
    --query 'data[0].id' --raw-output)
echo "  IGW: $IGW_ID"

# --- Route Table ---
echo "→ Updating default route table..."
RT_ID=$(oci network route-table list \
  --compartment-id "$COMPARTMENT_OCID" \
  --vcn-id "$VCN_ID" \
  --query 'data[0].id' --raw-output)

oci network route-table update \
  --rt-id "$RT_ID" \
  --route-rules "[{\"destination\":\"0.0.0.0/0\",\"destinationType\":\"CIDR_BLOCK\",\"networkEntityId\":\"$IGW_ID\"}]" \
  --force \
  --wait-for-state AVAILABLE >/dev/null 2>&1
echo "  Route table updated"

# --- Security List ---
echo "→ Updating default security list..."
SL_ID=$(oci network security-list list \
  --compartment-id "$COMPARTMENT_OCID" \
  --vcn-id "$VCN_ID" \
  --query 'data[0].id' --raw-output)

INGRESS='[{"source":"0.0.0.0/0","protocol":"6","tcpOptions":{"destinationPortRange":{"min":22,"max":22}}}]'
EGRESS='[{"destination":"0.0.0.0/0","protocol":"all"}]'

oci network security-list update \
  --security-list-id "$SL_ID" \
  --ingress-security-rules "$INGRESS" \
  --egress-security-rules "$EGRESS" \
  --force \
  --wait-for-state AVAILABLE >/dev/null 2>&1
echo "  Security list updated (SSH in, all out)"

# --- Subnet ---
echo "→ Creating subnet..."
SUBNET_ID=$(oci network subnet create \
  --compartment-id "$COMPARTMENT_OCID" \
  --vcn-id "$VCN_ID" \
  --cidr-block "$SUBNET_CIDR" \
  --display-name "${DISPLAY_NAME}-subnet" \
  --route-table-id "$RT_ID" \
  --security-list-ids "[\"$SL_ID\"]" \
  --query 'data.id' --raw-output \
  --wait-for-state AVAILABLE 2>/dev/null || \
  oci network subnet list \
    --compartment-id "$COMPARTMENT_OCID" \
    --vcn-id "$VCN_ID" \
    --display-name "${DISPLAY_NAME}-subnet" \
    --query 'data[0].id' --raw-output)
echo "  Subnet: $SUBNET_ID"

# --- Find Ubuntu 24.04 aarch64 image ---
echo "→ Finding Ubuntu 24.04 ARM image..."
IMAGE_ID=$(oci compute image list \
  --compartment-id "$COMPARTMENT_OCID" \
  --operating-system "Canonical Ubuntu" \
  --operating-system-version "24.04" \
  --shape "$SHAPE" \
  --sort-by TIMECREATED --sort-order DESC \
  --query 'data[0].id' --raw-output)
echo "  Image: $IMAGE_ID"

# --- SSH key ---
SSH_PUB_KEY=$(cat "$SSH_PUBLIC_KEY_PATH")

# --- Compute Instance ---
echo "→ Creating compute instance (this takes 2-3 min)..."
INSTANCE_ID=$(oci compute instance launch \
  --compartment-id "$COMPARTMENT_OCID" \
  --availability-domain "$AD" \
  --shape "$SHAPE" \
  --shape-config "{\"ocpus\":$OCPUS,\"memoryInGBs\":$MEMORY_GB}" \
  --display-name "$DISPLAY_NAME" \
  --image-id "$IMAGE_ID" \
  --subnet-id "$SUBNET_ID" \
  --assign-public-ip true \
  --ssh-authorized-keys-file <(echo "$SSH_PUB_KEY") \
  --query 'data.id' --raw-output \
  --wait-for-state RUNNING 2>/dev/null)
echo "  Instance: $INSTANCE_ID"

# --- Get public IP ---
echo "→ Getting public IP..."
VNIC_ID=$(oci compute instance list-vnics \
  --instance-id "$INSTANCE_ID" \
  --query 'data[0].id' --raw-output)

PUBLIC_IP=$(oci network vnic get \
  --vnic-id "$VNIC_ID" \
  --query 'data."public-ip"' --raw-output)

echo ""
echo "=== Deploy Complete ==="
echo "Public IP: $PUBLIC_IP"
echo ""
echo "Next steps:"
echo "  1. Wait ~60s for SSH to become available"
echo "  2. Run: ./setup.sh $PUBLIC_IP"
echo ""

# Save state for teardown
cat > "$SCRIPT_DIR/.deploy-state" <<EOF
INSTANCE_ID=$INSTANCE_ID
VCN_ID=$VCN_ID
SUBNET_ID=$SUBNET_ID
IGW_ID=$IGW_ID
PUBLIC_IP=$PUBLIC_IP
EOF

echo "State saved to .deploy-state (used by teardown.sh)"
