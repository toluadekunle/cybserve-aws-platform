terraform {
  required_version = ">= 1.6.0"

  cloud {
    organization = "Cybserve"

    workspaces {
      name = "ha-3tier-shared-prod"
    }
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      Workspace   = "shared"
      ManagedBy   = "terraform"
      Owner       = "tolu@cybserve.co.uk"
    }
  }
}
