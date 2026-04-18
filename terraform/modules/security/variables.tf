variable "project_name" {
  type = string
}

variable "environment" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "vpc_cidr" {
  description = "Kept for future CIDR-based rules (e.g. operator jump hosts)"
  type        = string
}

variable "alb_listen_ports" {
  description = "External ALB listener ports"
  type        = list(number)
  default     = [80, 443]
}

variable "web_listen_port" {
  description = "Web tier listener port"
  type        = number
  default     = 80
}

variable "app_listen_port" {
  description = "App tier + internal ALB listener port"
  type        = number
  default     = 5000
}

variable "db_port" {
  description = "Database port"
  type        = number
  default     = 3306
}
