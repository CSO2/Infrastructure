terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # NOTE: Backend is intentionally disabled to avoid touching the production
  # S3/DynamoDB state in us-east-1. Uncomment and configure the backend when
  # you are ready to migrate or manage remote state in ap-southeast-1.
  # backend "s3" {
  #   bucket         = "cso2-ecommerce-tf-state-239090154252-ap-southeast-1"
  #   key            = "terraform.tfstate"
  #   region         = "ap-southeast-1"
  #   dynamodb_table = "cso2-ecommerce-tf-lock"
  #   encrypt        = true
  # }
}

provider "aws" {
  # Force the provider region to Singapore for all Terraform operations
  region = "ap-southeast-1"
}
