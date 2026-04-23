########################################
# Outputs consumed by burst-layer workspaces via
# tfe_outputs.nonsensitive_values. Same coupling-minimisation
# principle as terraform/shared/outputs.tf — only expose what
# burst layer actually consumes, plus a small operator-
# visibility set.
########################################

########################################
# Consumed by burst layer — KMS ARNs
########################################
output "kms_rds_arn" {
  description = "CMK for Aurora encryption + snapshots + Backup vault"
  value       = aws_kms_key.rds.arn
}

output "kms_secrets_arn" {
  description = "CMK for Secrets Manager secrets in burst layer"
  value       = aws_kms_key.secrets.arn
}

output "kms_cloudwatch_logs_arn" {
  description = "CMK for CloudWatch log groups (WAF logs, SSM sessions, app logs)"
  value       = aws_kms_key.cloudwatch_logs.arn
}

output "kms_ebs_arn" {
  description = "CMK for EBS volumes (default applies, but burst layer can reference explicitly)"
  value       = aws_kms_key.ebs.arn
}

########################################
# Consumed by burst layer — Private CA
########################################
output "private_ca_arn" {
  description = "ACM Private CA ARN — burst layer requests internal TLS certs from this"
  value       = aws_acmpca_certificate_authority.internal.arn
}

########################################
# Consumed by burst layer — DNS + public certs
########################################
output "route53_zone_prod_id" {
  description = "Prod Route53 hosted zone ID — burst layer writes the A-alias here"
  value       = aws_route53_zone.prod.zone_id
}

output "route53_zone_prod_name" {
  description = "Prod Route53 zone FQDN"
  value       = aws_route53_zone.prod.name
}

output "route53_zone_staging_id" {
  description = "Staging Route53 hosted zone ID"
  value       = aws_route53_zone.staging.zone_id
}

output "route53_zone_staging_name" {
  description = "Staging Route53 zone FQDN"
  value       = aws_route53_zone.staging.name
}

output "acm_cert_prod_arn" {
  description = "Public ACM cert for prod external ALB"
  value       = aws_acm_certificate_validation.prod.certificate_arn
}

output "acm_cert_staging_arn" {
  description = "Public ACM cert for staging external ALB"
  value       = aws_acm_certificate_validation.staging.certificate_arn
}

########################################
# Consumed by burst layer — audit log bucket
########################################
output "alb_log_bucket_id" {
  description = "Shared ALB access log bucket (lives in permanent, survives compute rebuild)"
  value       = aws_s3_bucket.alb_logs.id
}

output "flow_log_bucket_arn" {
  description = "VPC flow log archive bucket (burst layer configures flow logs to it)"
  value       = aws_s3_bucket.flow_logs.arn
}

########################################
# Consumed by burst layer — SSM AMI parameter names
########################################
output "ssm_param_prod_web_ami" {
  description = "SSM parameter name holding the prod web-tier AMI ID"
  value       = aws_ssm_parameter.ami["prod-web"].name
}

output "ssm_param_prod_app_ami" {
  description = "SSM parameter name holding the prod app-tier AMI ID"
  value       = aws_ssm_parameter.ami["prod-app"].name
}

output "ssm_param_staging_web_ami" {
  description = "SSM parameter name holding the staging web-tier AMI ID"
  value       = aws_ssm_parameter.ami["staging-web"].name
}

output "ssm_param_staging_app_ami" {
  description = "SSM parameter name holding the staging app-tier AMI ID"
  value       = aws_ssm_parameter.ami["staging-app"].name
}

########################################
# Operator visibility only — Route53 NS records
########################################
output "route53_prod_name_servers" {
  description = "OPERATOR: NS records for prod zone — set these on the parent (cybserve.io) registrar, one-time"
  value       = aws_route53_zone.prod.name_servers
}

output "route53_staging_name_servers" {
  description = "OPERATOR: NS records for staging zone — set these on the parent registrar, one-time"
  value       = aws_route53_zone.staging.name_servers
}

########################################
# Operator visibility — IAM role ARNs
########################################
output "hcp_role_arns" {
  description = "OPERATOR: HCP workspace role ARNs — paste into each workspace's 'Dynamic Credentials' config"
  value       = { for k, r in aws_iam_role.hcp_workspace : k => r.arn }
}

output "github_packer_role_arn" {
  description = "OPERATOR: role assumed by the deploy-app workflow (companion app repo)"
  value       = aws_iam_role.github_packer.arn
}

output "breakglass_admin_role_arn" {
  description = "OPERATOR: break-glass admin role — assume from SSO with MFA"
  value       = aws_iam_role.breakglass_admin.arn
}

output "cis_alarms_sns_topic_arn" {
  description = "OPERATOR: subscribe your email/Slack webhook to this topic for CIS alarm notifications"
  value       = aws_sns_topic.cis_alarms.arn
}
