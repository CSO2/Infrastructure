terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    bucket         = "CHANGE_ME_TO_YOUR_BUCKET_NAME"
    key            = "terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "CHANGE_ME_TO_YOUR_DYNAMODB_TABLE_NAME"
    encrypt        = true
  }
}

provider "aws" {
  region = var.region
}
