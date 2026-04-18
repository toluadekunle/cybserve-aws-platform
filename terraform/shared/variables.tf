variable "project_name" {
  description = "Short project identifier used in all resource names and tags"
  type        = string
  default     = "ha-3tier"
}

variable "environment" {
  description = "Deployment environment (prod, staging, dev)"
  type        = string
  default     = "prod"
}

variable "aws_region" {
  description = "AWS region for all shared resources"
  type        = string
  default     = "eu-west-2"
}

# ── Networking ─────────────────────────────────────────────
variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  description = "Availability zones for subnet spread (minimum 2)"
  type        = list(string)
  default     = ["eu-west-2a", "eu-west-2b"]

  validation {
    condition     = length(var.availability_zones) >= 2
    error_message = "At least 2 availability zones are required for Multi-AZ resilience."
  }
}

variable "public_subnet_cidrs" {
  description = "CIDRs for public subnets (one per AZ)"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_app_subnet_cidrs" {
  description = "CIDRs for private application subnets (one per AZ)"
  type        = list(string)
  default     = ["10.0.11.0/24", "10.0.12.0/24"]
}

variable "private_data_subnet_cidrs" {
  description = "CIDRs for private data subnets (one per AZ)"
  type        = list(string)
  default     = ["10.0.21.0/24", "10.0.22.0/24"]
}

# ── Database ───────────────────────────────────────────────
variable "db_name" {
  description = "Initial database name"
  type        = string
  default     = "appdb"
}

variable "db_master_username" {
  description = "RDS master username (used only for bootstrap)"
  type        = string
  default     = "dbadmin"
}

variable "db_app_username" {
  description = "Application database user (least privilege)"
  type        = string
  default     = "app_user"
}

variable "db_instance_class" {
  description = "RDS instance class"
  type        = string
  default     = "db.t3.micro"
}

variable "db_allocated_storage" {
  description = "RDS allocated storage in GB"
  type        = number
  default     = 20
}

variable "db_backup_retention_period" {
  description = "Number of days to retain automated backups"
  type        = number
  default     = 14

  validation {
    condition     = var.db_backup_retention_period >= 7
    error_message = "Backup retention must be at least 7 days for production workloads."
  }
}

# ── DNS / TLS ──────────────────────────────────────────────
variable "enable_route53" {
  description = "Whether to create a Route53 hosted zone and ACM certificate"
  type        = bool
  default     = true
}

variable "route53_zone_name" {
  description = "Subdomain to delegate to Route53 (e.g. app.cybserve.co.uk). Required when enable_route53 = true."
  type        = string
  default     = "app.cybserve.co.uk"

  validation {
    condition     = !var.enable_route53 ? true : length(var.route53_zone_name) > 0
    error_message = "route53_zone_name must be non-empty when enable_route53 is true."
  }
}

# ── Operational ────────────────────────────────────────────
variable "alb_log_retention_days" {
  description = "CloudWatch log retention for ALB + session manager logs"
  type        = number
  default     = 90
}

# ── Port contract (passed to security module) ─────────────
variable "alb_listen_ports" {
  description = "External ALB listener ports. Must contain 80 and 443 for the HTTP→HTTPS redirect pattern."
  type        = list(number)
  default     = [80, 443]
}

variable "web_listen_port" {
  description = "Web tier listener port (Nginx)"
  type        = number
  default     = 80
}

variable "app_listen_port" {
  description = "App tier listener port (Flask) and internal ALB listener port"
  type        = number
  default     = 5000
}

variable "db_port" {
  description = "Database port (MariaDB/MySQL = 3306)"
  type        = number
  default     = 3306
}
