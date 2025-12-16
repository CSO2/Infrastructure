#!/bin/bash
# Script to update OpenSearch K8s endpoint with control plane IP

set -euo pipefail

TERRAFORM_DIR="../../../terraform"
K8S_SERVICE_FILE="./service.yaml"

echo "==> Fetching control plane private IP from Terraform..."

cd "$TERRAFORM_DIR"

# Get control plane private IP
CONTROL_PLANE_IP=$(terraform output -json | jq -r '.control_plane_public_ips.value[0]')

if [ -z "$CONTROL_PLANE_IP" ] || [ "$CONTROL_PLANE_IP" == "null" ]; then
  echo "ERROR: Could not get control plane IP from Terraform"
  echo "Run 'terraform apply' first or check outputs"
  exit 1
fi

# For private IP, we need to get it from AWS or state
# Using terraform show to get private IP
CONTROL_PLANE_PRIVATE_IP=$(terraform show -json | jq -r '.values.root_module.child_modules[] | select(.address=="module.ec2") | .resources[] | select(.type=="aws_instance" and .name=="control_plane") | .values.private_ip' | head -n1)

if [ -z "$CONTROL_PLANE_PRIVATE_IP" ] || [ "$CONTROL_PLANE_PRIVATE_IP" == "null" ]; then
  echo "WARNING: Could not get private IP, using public IP: $CONTROL_PLANE_IP"
  CONTROL_PLANE_PRIVATE_IP="$CONTROL_PLANE_IP"
fi

echo "==> Control Plane IP: $CONTROL_PLANE_PRIVATE_IP"
echo ""

cd - > /dev/null

# Update the Kubernetes service file
echo "==> Updating $K8S_SERVICE_FILE..."

sed -i.bak "s/- ip: .*/- ip: $CONTROL_PLANE_PRIVATE_IP  # Control plane private IP/" "$K8S_SERVICE_FILE"

echo "==> Updated! Backup saved to ${K8S_SERVICE_FILE}.bak"
echo ""
echo "Current endpoint configuration:"
grep -A2 "addresses:" "$K8S_SERVICE_FILE" | grep "ip:"
echo ""
echo "✅ Done! Deploy to Kubernetes with:"
echo "   kubectl apply -k ../../overlays/dev/"
