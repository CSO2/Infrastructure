#!/bin/bash

# setup_prereqs.sh
# Installs prerequisites for the CSO2 infrastructure project on macOS.

set -e

echo "Starting prerequisite setup for CSO2..."

# Check for Homebrew
if ! command -v brew &> /dev/null; then
    echo "Homebrew not found. Please install Homebrew first: https://brew.sh/"
    exit 1
fi

echo "Updating Homebrew..."
brew update

# Function to install a package if not present
install_package() {
    PACKAGE=$1
    CMD=$2
    if ! command -v $CMD &> /dev/null; then
        echo "Installing $PACKAGE..."
        brew install $PACKAGE
    else
        echo "$PACKAGE is already installed."
    fi
}

# Install Terraform
install_package "terraform" "terraform"

# Install Ansible
install_package "ansible" "ansible"

# Install AWS CLI
install_package "awscli" "aws"

# Install Kubectl
install_package "kubectl" "kubectl"

echo "Prerequisite setup complete."
echo "Please ensure you have configured your AWS credentials using 'aws configure'."

# Terraform Backend Setup
read -p "Do you want to set up Terraform backend (S3 & DynamoDB)? (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    read -p "Enter AWS Region (default: us-east-1): " AWS_REGION
    AWS_REGION=${AWS_REGION:-us-east-1}
    
    read -p "Enter Project Name (default: cso2-ecommerce): " PROJECT_NAME
    PROJECT_NAME=${PROJECT_NAME:-cso2-ecommerce}
    
    BUCKET_NAME="${PROJECT_NAME}-tf-state-$(date +%s)"
    TABLE_NAME="${PROJECT_NAME}-tf-lock"

    echo "Creating S3 bucket: $BUCKET_NAME..."
    aws s3api create-bucket --bucket $BUCKET_NAME --region $AWS_REGION --create-bucket-configuration LocationConstraint=$AWS_REGION || aws s3 mb s3://$BUCKET_NAME --region $AWS_REGION

    echo "Enabling versioning on bucket..."
    aws s3api put-bucket-versioning --bucket $BUCKET_NAME --versioning-configuration Status=Enabled

    echo "Creating DynamoDB table: $TABLE_NAME..."
    aws dynamodb create-table \
        --table-name $TABLE_NAME \
        --attribute-definitions AttributeName=LockID,AttributeType=S \
        --key-schema AttributeName=LockID,KeyType=HASH \
        --provisioned-throughput ReadCapacityUnits=5,WriteCapacityUnits=5 \
        --region $AWS_REGION

    echo "Backend setup complete."
    echo "Bucket: $BUCKET_NAME"
    echo "DynamoDB Table: $TABLE_NAME"
    echo "Please update your terraform/provider.tf with these details."
fi
