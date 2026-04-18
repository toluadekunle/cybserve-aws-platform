variable "project_name" {
  description = "Project name prefix"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "public_subnet_ids" {
  description = "Public subnet IDs for the external ALB"
  type        = list(string)
}

variable "private_subnet_ids" {
  description = "Private subnet IDs for the internal ALB"
  type        = list(string)
}

variable "alb_sg_id" {
  description = "Security group ID for the external ALB"
  type        = string
}

variable "int_alb_sg_id" {
  description = "Security group ID for the internal ALB"
  type        = string
}

variable "certificate_arn" {
  description = "ACM certificate ARN for HTTPS listener (empty disables HTTPS)"
  type        = string
  default     = ""
}

variable "access_log_bucket_id" {
  description = "Optional external S3 bucket for ALB access logs. When set, the module uses this bucket instead of creating its own. This lets the long-lived shared workspace own the log bucket so it survives compute rebuilds."
  type        = string
  default     = ""
}

variable "web_target_port" {
  description = "Port the web tier listens on"
  type        = number
  default     = 80
}

variable "app_target_port" {
  description = "Port the app tier listens on"
  type        = number
  default     = 5000
}

variable "web_health_path" {
  description = "Health check path for web target group"
  type        = string
  default     = "/health"
}

variable "app_health_path" {
  description = "Health check path for app target group"
  type        = string
  default     = "/api/ready"
}
