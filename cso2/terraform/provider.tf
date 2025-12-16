terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    bucket         = "cso2-ecommerce-tf-state-239090154252-us-east-1"
    key            = "terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "cso2-ecommerce-tf-lock"
    encrypt        = true
  }
}

provider "aws" {
  region = var.region
}
