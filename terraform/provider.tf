# Terraform Provider Configuration

terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Backend configuration for state storage
  # Uncomment and configure for remote state
  # backend "s3" {
  #   bucket         = "my-terraform-state-bucket"
  #   key            = "eventbridge-orchestrator/terraform.tfstate"
  #   region         = "us-east-1"
  #   encrypt        = true
  #   dynamodb_table = "terraform-state-lock"
  # }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = merge(
      var.common_tags,
      {
        Environment = var.environment
        Project     = var.project_name
      }
    )
  }
}