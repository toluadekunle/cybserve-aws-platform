variable "project_name" {
  type = string
}

variable "environment" {
  type = string
}

variable "tier" {
  description = "Logical tier name (web, app)"
  type        = string
}

variable "vpc_id" {
  type = string
}

variable "subnet_ids" {
  type = list(string)
}

variable "security_group_id" {
  type = string
}

variable "ami_id" {
  description = "Packer-built AMI ID"
  type        = string
}

variable "instance_type" {
  type    = string
  default = "t3.small"
}

variable "user_data" {
  description = "Base64-encoded user data"
  type        = string
}

variable "target_group_arn" {
  type = string
}

variable "asg_min_size" {
  type    = number
  default = 2
}

variable "asg_max_size" {
  type    = number
  default = 4
}

variable "asg_desired_capacity" {
  type    = number
  default = 2
}

variable "needs_secrets_access" {
  description = "Whether this tier needs Secrets Manager read access (app=true, web=false)"
  type        = bool
  default     = false
}

variable "secret_arn" {
  description = "Exact Secrets Manager ARN to grant read access to (only used when needs_secrets_access=true)"
  type        = string
  default     = "*"
}
