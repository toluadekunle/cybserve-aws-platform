variable "project_name" {
  description = "Project name prefix"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "db_name" {
  description = "Initial database name"
  type        = string
}

variable "db_username" {
  description = "Master username"
  type        = string
}

variable "db_password" {
  description = "Master password (from Secrets Manager)"
  type        = string
  sensitive   = true
}

variable "db_instance_class" {
  description = "RDS instance class"
  type        = string
  default     = "db.t3.micro"
}

variable "db_allocated_storage" {
  description = "Initial storage (GB)"
  type        = number
  default     = 20
}

variable "db_max_allocated_storage" {
  description = "Autoscaling storage ceiling (GB)"
  type        = number
  default     = 100
}

variable "backup_retention_period" {
  description = "Days to retain automated backups"
  type        = number
  default     = 14

  validation {
    condition     = var.backup_retention_period >= 7
    error_message = "Backup retention must be at least 7 days for production."
  }
}

variable "engine" {
  description = "RDS engine"
  type        = string
  default     = "mariadb"
}

variable "engine_version" {
  description = "RDS engine version"
  type        = string
  default     = "10.11"
}

variable "db_parameter_group_family" {
  description = "Parameter group family"
  type        = string
  default     = "mariadb10.11"
}

variable "private_data_subnet_ids" {
  description = "Private data subnet IDs (for DB subnet group)"
  type        = list(string)
}

variable "rds_security_group_id" {
  description = "Security group ID for RDS"
  type        = string
}
