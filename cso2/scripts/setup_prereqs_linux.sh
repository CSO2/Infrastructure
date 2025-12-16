#!/usr/bin/env bash
set -euo pipefail

echo "Starting prerequisite setup for CSO2..."

if ! command -v apt-get >/dev/null 2>&1; then
  echo "This script currently supports Debian/Ubuntu (apt)."
  exit 1
fi

sudo apt-get update -y
sudo apt-get install -y ca-certificates curl gnupg lsb-release unzip jq

install_terraform() {
  if command -v terraform >/dev/null 2>&1; then
    echo "Terraform is already installed."
    return
  fi

  echo "Installing Terraform (HashiCorp repo)..."
  sudo install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/hashicorp.gpg
  echo "deb [signed-by=/etc/apt/keyrings/hashicorp.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | \
    sudo tee /etc/apt/sources.list.d/hashicorp.list >/dev/null
  sudo apt-get update -y
  sudo apt-get install -y terraform
}

install_kubectl() {
  if command -v kubectl >/dev/null 2>&1; then
    echo "kubectl is already installed."
    return
  fi

  echo "Installing kubectl (Kubernetes apt repo)..."
  sudo install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.30/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
  echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.30/deb/ /" | \
    sudo tee /etc/apt/sources.list.d/kubernetes.list >/dev/null
  sudo apt-get update -y
  sudo apt-get install -y kubectl
}

install_ansible() {
  if command -v ansible >/dev/null 2>&1; then
    echo "Ansible is already installed."
    return
  fi
  echo "Installing Ansible..."
  sudo apt-get install -y ansible
}

install_awscli_v2() {
  if command -v aws >/dev/null 2>&1; then
    echo "AWS CLI is already installed: $(aws --version 2>&1)"
    return
  fi

  echo "Installing AWS CLI v2..."
  tmpdir="$(mktemp -d)"
  curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "$tmpdir/awscliv2.zip"
  unzip -q "$tmpdir/awscliv2.zip" -d "$tmpdir"
  sudo "$tmpdir/aws/install"
  rm -rf "$tmpdir"
}

install_terraform
install_ansible
install_awscli_v2
install_kubectl

echo "Prerequisite setup complete."
echo "Make sure AWS credentials are configured (aws configure / SSO / env vars)."

read -r -p "Set up Terraform backend (S3 + DynamoDB)? (y/n) " reply
if [[ "${reply}" =~ ^[Yy]$ ]]; then
  read -r -p "AWS Region (default: us-east-1): " AWS_REGION
  AWS_REGION="${AWS_REGION:-us-east-1}"

  read -r -p "Project Name (default: cso2-ecommerce): " PROJECT_NAME
  PROJECT_NAME="${PROJECT_NAME:-cso2-ecommerce}"

  AWS_ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
  BUCKET_NAME="${PROJECT_NAME}-tf-state-${AWS_ACCOUNT_ID}-${AWS_REGION}"
  TABLE_NAME="${PROJECT_NAME}-tf-lock"

  echo "Creating S3 bucket: ${BUCKET_NAME}..."
  if [[ "${AWS_REGION}" == "us-east-1" ]]; then
    aws s3api create-bucket --bucket "${BUCKET_NAME}" --region "${AWS_REGION}" >/dev/null
  else
    aws s3api create-bucket --bucket "${BUCKET_NAME}" --region "${AWS_REGION}" \
      --create-bucket-configuration "LocationConstraint=${AWS_REGION}" >/dev/null
  fi

  echo "Applying bucket security defaults..."
  aws s3api put-public-access-block --bucket "${BUCKET_NAME}" \
    --public-access-block-configuration BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true

  aws s3api put-bucket-versioning --bucket "${BUCKET_NAME}" \
    --versioning-configuration Status=Enabled

  aws s3api put-bucket-encryption --bucket "${BUCKET_NAME}" \
    --server-side-encryption-configuration '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'

  aws s3api put-bucket-policy --bucket "${BUCKET_NAME}" --policy "{
    \"Version\":\"2012-10-17\",
    \"Statement\":[
      {
        \"Sid\":\"DenyInsecureTransport\",
        \"Effect\":\"Deny\",
        \"Principal\":\"*\",
        \"Action\":\"s3:*\",
        \"Resource\":[
          \"arn:aws:s3:::${BUCKET_NAME}\",
          \"arn:aws:s3:::${BUCKET_NAME}/*\"
        ],
        \"Condition\":{\"Bool\":{\"aws:SecureTransport\":\"false\"}}
      }
    ]
  }" >/dev/null

  echo "Creating DynamoDB table: ${TABLE_NAME}..."
  aws dynamodb create-table \
    --table-name "${TABLE_NAME}" \
    --attribute-definitions AttributeName=LockID,AttributeType=S \
    --key-schema AttributeName=LockID,KeyType=HASH \
    --billing-mode PAY_PER_REQUEST \
    --region "${AWS_REGION}" >/dev/null

  echo "Backend setup complete:"
  echo "  Bucket: ${BUCKET_NAME}"
  echo "  DynamoDB Table: ${TABLE_NAME}"
  echo "Update your Terraform backend config to use these."
fi
