output "alb_sg_id" {
  description = "External ALB security group"
  value       = aws_security_group.alb.id
}

output "int_alb_sg_id" {
  description = "Internal ALB security group"
  value       = aws_security_group.int_alb.id
}

output "web_sg_id" {
  description = "Web tier security group"
  value       = aws_security_group.web.id
}

output "app_sg_id" {
  description = "App tier security group"
  value       = aws_security_group.app.id
}

output "rds_sg_id" {
  description = "RDS security group"
  value       = aws_security_group.rds.id
}
