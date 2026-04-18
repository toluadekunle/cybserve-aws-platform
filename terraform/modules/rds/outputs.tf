output "db_endpoint" {
  description = "RDS endpoint in host:port format. NOT sensitive — the host is not a secret, credentials are."
  value       = aws_db_instance.main.endpoint
}

output "db_address" {
  description = "RDS hostname (no port)"
  value       = aws_db_instance.main.address
}

output "db_port" {
  description = "RDS port"
  value       = aws_db_instance.main.port
}

output "db_arn" {
  description = "RDS instance ARN"
  value       = aws_db_instance.main.arn
}

output "db_resource_id" {
  description = "RDS resource ID (used for Performance Insights IAM)"
  value       = aws_db_instance.main.resource_id
}

output "db_subnet_group_name" {
  description = "DB subnet group name"
  value       = aws_db_subnet_group.main.name
}
