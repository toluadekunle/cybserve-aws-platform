terraform {
  required_version = ">= 1.6.0"

  cloud {
    organization = "Cybserve"

    workspaces {
      name = "ha-3tier-compute-prod"
    }
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    tfe = {
      source  = "hashicorp/tfe"
      version = "~> 0.55"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      Workspace   = "compute"
      ManagedBy   = "terraform"
      Owner       = "tolu@cybserve.co.uk"
    }
  }
}
