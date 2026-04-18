output "alb_dns_name" {
  description = "External ALB DNS name"
  value       = module.alb.alb_dns_name
}

output "app_url" {
  description = "Public HTTPS URL for the application"
  value       = local.route53_zone_name != "" ? "https://${local.route53_zone_name}" : "http://${module.alb.alb_dns_name}"
}

output "web_asg_name" {
  description = "Web tier ASG name (used by deploy-app.yml for instance refresh)"
  value       = module.web_tier.asg_name
}

output "app_asg_name" {
  description = "App tier ASG name (used by deploy-app.yml for instance refresh)"
  value       = module.app_tier.asg_name
}

output "waf_web_acl_id" {
  description = "WAF web ACL ID (empty when WAF disabled)"
  value       = var.enable_waf ? aws_wafv2_web_acl.main[0].id : ""
}
