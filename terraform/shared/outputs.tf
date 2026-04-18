########################################
# Shared workspace outputs
#
# Principle: minimise coupling. Only expose what compute
# genuinely consumes via tfe_outputs, plus a small set of
# operator-visibility outputs that are useful to see in
# the HCP UI but never read by compute.
#
# Everything consumed by compute is also marked
# non-sensitive so tfe_outputs.nonsensitive_values
# surfaces it.
########################################

########################################
# Consumed by compute (network)
########################################
output "vpc_id" {
  description = "VPC ID — consumed by compute"
  value       = module.vpc.vpc_id
}

output "public_subnet_ids" {
  description = "Public subnet IDs — external ALB consumer"
  value       = module.vpc.public_subnet_ids
}

output "private_app_subnet_ids" {
  description = "Private app subnet IDs — ASGs and internal ALB consumer"
  value       = module.vpc.private_app_subnet_ids
}

########################################
# Consumed by compute (security)
########################################
output "alb_sg_id" {
  description = "External ALB SG — consumed by compute"
  value       = module.security.alb_sg_id
}

output "int_alb_sg_id" {
  description = "Internal ALB SG — consumed by compute"
  value       = module.security.int_alb_sg_id
}

output "web_sg_id" {
  description = "Web tier SG — consumed by compute"
  value       = module.security.web_sg_id
}

output "app_sg_id" {
  description = "App tier SG — consumed by compute"
  value       = module.security.app_sg_id
}

########################################
# Consumed by compute (database)
# Note: rds_endpoint, db_name, and db_app_username are
# passed through to app userdata. A cleaner pattern is to
# have the app read all four values from the secret at
# boot, at which point only db_app_secret_id/arn need
# to cross workspace boundaries. Left as a future refactor
# (requires a change in app.py, not just infra).
########################################
output "rds_endpoint" {
  description = "RDS host:port — consumed by compute for app userdata"
  value       = module.rds.db_endpoint
}

output "db_name" {
  description = "Initial database name — consumed by compute for app userdata"
  value       = var.db_name
}

output "db_app_username" {
  description = "Application DB user — consumed by compute for app userdata"
  value       = var.db_app_username
}

output "db_app_secret_arn" {
  description = "App user secret ARN — consumed by compute (IAM scope on app tier)"
  value       = aws_secretsmanager_secret.db_app.arn
}

output "db_app_secret_id" {
  description = "App user secret ID — consumed by compute (userdata env var)"
  value       = aws_secretsmanager_secret.db_app.id
}

########################################
# Consumed by compute (DNS / TLS / logging)
########################################
output "certificate_arn" {
  description = "ACM certificate ARN — consumed by compute HTTPS listener. Empty when enable_route53 = false."
  value       = var.enable_route53 ? aws_acm_certificate.main[0].arn : ""
}

output "route53_zone_id" {
  description = "Route53 zone ID — consumed by compute A-alias record"
  value       = var.enable_route53 ? aws_route53_zone.app[0].zone_id : ""
}

output "route53_zone_name" {
  description = "Route53 zone FQDN — consumed by compute A-alias record"
  value       = var.enable_route53 ? aws_route53_zone.app[0].name : ""
}

output "alb_log_bucket_id" {
  description = "Shared ALB access-log bucket — consumed by ALB module"
  value       = aws_s3_bucket.alb_logs.id
}

########################################
# Operator visibility only
# NOT consumed by compute. Here so they appear in the HCP
# UI without needing CLI access to shared state.
########################################
output "route53_name_servers" {
  description = "OPERATOR: NS records to set in GoDaddy for one-time subdomain delegation"
  value       = var.enable_route53 ? aws_route53_zone.app[0].name_servers : []
}
