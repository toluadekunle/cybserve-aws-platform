variable "project_name" {
  description = "Short project identifier — must match shared workspace"
  type        = string
  default     = "ha-3tier"
}

variable "environment" {
  description = "Deployment environment — must match shared workspace"
  type        = string
  default     = "prod"
}

variable "aws_region" {
  description = "AWS region — must match shared workspace"
  type        = string
  default     = "eu-west-2"
}

variable "shared_workspace_name" {
  description = "Name of the HCP workspace holding shared-layer outputs"
  type        = string
  default     = "ha-3tier-shared-prod"
}

variable "shared_organization" {
  description = "HCP Terraform organization"
  type        = string
  default     = "Cybserve"
}

# ── AMIs ───────────────────────────────────────────────────
# Pinned AMIs from Packer build. deploy-app.yml commits these back on change.
variable "web_ami_id" {
  description = "Packer-built AMI for web tier (Nginx)"
  type        = string
}

variable "app_ami_id" {
  description = "Packer-built AMI for app tier (Flask)"
  type        = string
}

# ── Instance sizing ────────────────────────────────────────
variable "web_instance_type" {
  description = "Instance type for web tier"
  type        = string
  default     = "t3.small"
}

variable "app_instance_type" {
  description = "Instance type for app tier"
  type        = string
  default     = "t3.small"
}

variable "web_asg_min_size" {
  description = "Web tier minimum instances"
  type        = number
  default     = 2
}

variable "web_asg_max_size" {
  description = "Web tier maximum instances"
  type        = number
  default     = 4
}

variable "web_asg_desired_capacity" {
  description = "Web tier desired instances"
  type        = number
  default     = 2
}

variable "app_asg_min_size" {
  description = "App tier minimum instances"
  type        = number
  default     = 2
}

variable "app_asg_max_size" {
  description = "App tier maximum instances"
  type        = number
  default     = 4
}

variable "app_asg_desired_capacity" {
  description = "App tier desired instances"
  type        = number
  default     = 2
}

# ── WAF ────────────────────────────────────────────────────
variable "enable_waf" {
  description = "Attach AWS Managed WAFv2 rules to external ALB"
  type        = bool
  default     = true
}

variable "waf_rate_limit" {
  description = "Maximum requests per 5-minute window per source IP (WAF rate-based rule)"
  type        = number
  default     = 2000
}
