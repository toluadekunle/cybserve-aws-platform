variable "project_name" {
  description = "Short project identifier used in resource names and tags"
  type        = string
  default     = "ha-3tier"
}

variable "aws_region" {
  description = "Primary AWS region"
  type        = string
  default     = "eu-west-2"
}

variable "owner_email" {
  description = "Human owner — tagged on every resource"
  type        = string
  default     = "tolu@cybserve.co.uk"
}

variable "github_org" {
  description = "GitHub organization (or user) hosting the platform repo + companion app repo"
  type        = string
  default     = "toluadekunle"
}

variable "github_platform_repo" {
  description = "GitHub repo name for the platform (this repo)"
  type        = string
  default     = "cybserve-aws-platform"
}

variable "github_app_repo" {
  description = "GitHub repo name for the companion application"
  type        = string
  default     = "cybserve-ha3-app"
}

variable "hcp_organization" {
  description = "HCP Terraform organization name"
  type        = string
  default     = "Cybserve"
}

variable "hcp_workspaces" {
  description = "HCP workspaces that assume AWS roles from this account, with their allowed run phases"
  type = map(object({
    phases = list(string) # subset of ["plan", "apply"]
  }))
  default = {
    ha-3tier-permanent-prod  = { phases = ["plan", "apply"] }
    ha-3tier-shared-prod     = { phases = ["plan", "apply"] }
    ha-3tier-compute-prod    = { phases = ["plan", "apply"] }
    ha-3tier-shared-staging  = { phases = ["plan", "apply"] }
    ha-3tier-compute-staging = { phases = ["plan", "apply"] }
  }
}

variable "parent_domain" {
  description = "Parent domain at whichever registrar holds cybserve.io — we never directly manage this, but it's where the NS delegation records for the subdomain zones below must be set (once)"
  type        = string
  default     = "cybserve.io"
}

variable "primary_domain" {
  description = "Public domain for the prod app — Route53 hosted zone is created for this FQDN"
  type        = string
  default     = "app.cybserve.io"
}

variable "staging_domain" {
  description = "Public domain for the staging app"
  type        = string
  default     = "app-staging.cybserve.io"
}

variable "audit_log_retention_years" {
  description = "Years to retain CloudTrail + Config history in S3 (compliance-locked)"
  type        = number
  default     = 1

  validation {
    condition     = var.audit_log_retention_years >= 1
    error_message = "Audit log retention must be at least 1 year for defensibility."
  }
}

variable "private_ca_common_name" {
  description = "Common Name for the internal Private CA root"
  type        = string
  default     = "cybserve-ha3-internal-ca"
}
