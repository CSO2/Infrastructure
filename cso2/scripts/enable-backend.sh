#!/bin/bash

# enable-backend.sh
# Enables S3 backend after resources are created

set -e

TERRAFORM_DIR="../terraform"
PROVIDER_FILE="$TERRAFORM_DIR/provider.tf"

echo "Enabling S3 backend in provider.tf..."

# Uncomment the backend block
sed -i 's/# Backend will be enabled after creating S3 bucket and DynamoDB table//' "$PROVIDER_FILE"
sed -i 's/#   backend "s3" {/  backend "s3" {/' "$PROVIDER_FILE"
sed -i 's/#     bucket/    bucket/' "$PROVIDER_FILE"
sed -i 's/#     key/    key/' "$PROVIDER_FILE"
sed -i 's/#     region/    region/' "$PROVIDER_FILE"
sed -i 's/#     dynamodb_table/    dynamodb_table/' "$PROVIDER_FILE"
sed -i 's/#     encrypt/    encrypt/' "$PROVIDER_FILE"
sed -i 's/#   }/  }/' "$PROVIDER_FILE"

echo "Backend configuration enabled."
echo "Now run: cd $TERRAFORM_DIR && terraform init -migrate-state"
