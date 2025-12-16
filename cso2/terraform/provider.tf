terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Remote backend for team collaboration
  backend "s3" {
    bucket         = "cso2-ecommerce-terraform-state"
    key            = "state/terraform.tfstate"
    region         = "ap-southeast-1"
    dynamodb_table = "cso2-ecommerce-terraform-locks"
    encrypt        = true
  }
}

provider "aws" {
  region = "ap-southeast-1"
}