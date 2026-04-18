output "alb_dns_name" {
  description = "External ALB DNS name (used for Route53 alias)"
  value       = aws_lb.external.dns_name
}

output "alb_zone_id" {
  description = "External ALB zone ID (used for Route53 alias)"
  value       = aws_lb.external.zone_id
}

output "external_alb_arn" {
  description = "External ALB ARN (used for WAF association)"
  value       = aws_lb.external.arn
}

output "internal_alb_dns" {
  description = "Internal ALB DNS name (web tier → app tier)"
  value       = aws_lb.internal.dns_name
}

output "web_target_group_arn" {
  description = "Web tier target group ARN"
  value       = aws_lb_target_group.web.arn
}

output "app_target_group_arn" {
  description = "App tier target group ARN"
  value       = aws_lb_target_group.app.arn
}
