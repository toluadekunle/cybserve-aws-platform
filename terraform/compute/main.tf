########################################
# 1. Read shared workspace outputs
#    (tfe_outputs.nonsensitive_values —
#     preferred over terraform_remote_state
#     in HCP Terraform)
########################################
data "tfe_outputs" "shared" {
  organization = var.shared_organization
  workspace    = var.shared_workspace_name
}

locals {
  shared = data.tfe_outputs.shared.nonsensitive_values

  vpc_id                 = local.shared.vpc_id
  public_subnet_ids      = local.shared.public_subnet_ids
  private_app_subnet_ids = local.shared.private_app_subnet_ids

  alb_sg_id      = local.shared.alb_sg_id
  int_alb_sg_id  = local.shared.int_alb_sg_id
  web_sg_id      = local.shared.web_sg_id
  app_sg_id      = local.shared.app_sg_id

  rds_endpoint     = local.shared.rds_endpoint
  db_name          = local.shared.db_name
  db_app_username  = local.shared.db_app_username
  db_app_secret_id = local.shared.db_app_secret_id
  db_app_secret_arn = local.shared.db_app_secret_arn

  certificate_arn  = local.shared.certificate_arn
  route53_zone_id  = local.shared.route53_zone_id
  route53_zone_name = local.shared.route53_zone_name
  alb_log_bucket_id = local.shared.alb_log_bucket_id
}

########################################
# 2. Application Load Balancers
#    External (public) + Internal (private)
#    ALB module now consumes shared log bucket.
########################################
module "alb" {
  source = "../modules/alb"

  project_name         = var.project_name
  environment          = var.environment
  vpc_id               = local.vpc_id
  public_subnet_ids    = local.public_subnet_ids
  private_subnet_ids   = local.private_app_subnet_ids
  alb_sg_id            = local.alb_sg_id
  int_alb_sg_id        = local.int_alb_sg_id
  certificate_arn      = local.certificate_arn
  access_log_bucket_id = local.alb_log_bucket_id
}

########################################
# 3. Web tier ASG
########################################
module "web_tier" {
  source = "../modules/ec2-asg"

  project_name     = var.project_name
  environment      = var.environment
  tier             = "web"
  vpc_id           = local.vpc_id
  subnet_ids       = local.private_app_subnet_ids
  security_group_id = local.web_sg_id

  ami_id           = var.web_ami_id
  instance_type    = var.web_instance_type
  target_group_arn = module.alb.web_target_group_arn

  asg_min_size         = var.web_asg_min_size
  asg_max_size         = var.web_asg_max_size
  asg_desired_capacity = var.web_asg_desired_capacity

  # Web tier does NOT need database credentials — pass empty
  needs_secrets_access = false
  secret_arn           = "*"

  user_data = base64encode(templatefile("${path.root}/../../scripts/web_userdata.sh", {
    app_tier_endpoint = module.alb.internal_alb_dns
    APP_TIER_ENDPOINT = module.alb.internal_alb_dns
    environment       = var.environment
    ENVIRONMENT       = var.environment
  }))
}

########################################
# 4. App tier ASG
#    Uses app_user secret, not master.
########################################
module "app_tier" {
  source = "../modules/ec2-asg"

  project_name     = var.project_name
  environment      = var.environment
  tier             = "app"
  vpc_id           = local.vpc_id
  subnet_ids       = local.private_app_subnet_ids
  security_group_id = local.app_sg_id

  ami_id           = var.app_ami_id
  instance_type    = var.app_instance_type
  target_group_arn = module.alb.app_target_group_arn

  asg_min_size         = var.app_asg_min_size
  asg_max_size         = var.app_asg_max_size
  asg_desired_capacity = var.app_asg_desired_capacity

  needs_secrets_access = true
  secret_arn           = local.db_app_secret_arn

  user_data = base64encode(templatefile("${path.root}/../../scripts/app_userdata.sh", {
    db_endpoint   = split(":", local.rds_endpoint)[0]
    db_name       = local.db_name
    db_user       = local.db_app_username
    db_secret_id  = local.db_app_secret_id
    DB_SECRET_ID  = local.db_app_secret_id
    environment   = var.environment
    aws_region    = var.aws_region
    AWS_REGION    = var.aws_region
  }))
}

########################################
# 5. WAFv2 on external ALB
#    v2: full baseline (CommonRuleSet +
#    KnownBadInputs + IpReputationList +
#    RateLimit) + CloudWatch logging.
########################################
resource "aws_wafv2_web_acl" "main" {
  count = var.enable_waf ? 1 : 0

  name        = "${var.project_name}-${var.environment}-waf"
  description = "Managed rule groups + rate limit for external ALB"
  scope       = "REGIONAL"

  default_action {
    allow {}
  }

  rule {
    name     = "AWS-ManagedRulesCommonRuleSet"
    priority = 1

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.project_name}-${var.environment}-waf-common"
      sampled_requests_enabled   = true
    }
  }

  rule {
    name     = "AWS-ManagedRulesKnownBadInputsRuleSet"
    priority = 2

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesKnownBadInputsRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.project_name}-${var.environment}-waf-badinputs"
      sampled_requests_enabled   = true
    }
  }

  rule {
    name     = "AWS-ManagedRulesAmazonIpReputationList"
    priority = 3

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesAmazonIpReputationList"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.project_name}-${var.environment}-waf-ipreputation"
      sampled_requests_enabled   = true
    }
  }

  rule {
    name     = "RateLimitPerIP"
    priority = 10

    action {
      block {}
    }

    statement {
      rate_based_statement {
        limit              = var.waf_rate_limit
        aggregate_key_type = "IP"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.project_name}-${var.environment}-waf-ratelimit"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${var.project_name}-${var.environment}-waf"
    sampled_requests_enabled   = true
  }

  tags = { Name = "${var.project_name}-${var.environment}-waf" }
}

resource "aws_wafv2_web_acl_association" "main" {
  count = var.enable_waf ? 1 : 0

  resource_arn = module.alb.external_alb_arn
  web_acl_arn  = aws_wafv2_web_acl.main[0].arn
}

# ── WAF logging ──
# Log group name MUST start with aws-waf-logs- for the
# WAF logging configuration API to accept it.
resource "aws_cloudwatch_log_group" "waf" {
  count = var.enable_waf ? 1 : 0

  name              = "aws-waf-logs-${var.project_name}-${var.environment}"
  retention_in_days = 90

  tags = { Name = "${var.project_name}-${var.environment}-waf-logs" }
}

resource "aws_wafv2_web_acl_logging_configuration" "main" {
  count = var.enable_waf ? 1 : 0

  resource_arn            = aws_wafv2_web_acl.main[0].arn
  log_destination_configs = [aws_cloudwatch_log_group.waf[0].arn]

  redacted_fields {
    single_header {
      name = "authorization"
    }
  }

  redacted_fields {
    single_header {
      name = "cookie"
    }
  }
}

########################################
# 6. Route53 alias — app.cybserve.co.uk → ALB
#    This is the automated binding that eliminates
#    the manual GoDaddy CNAME update on rebuild.
########################################
resource "aws_route53_record" "app" {
  count = local.route53_zone_id != "" ? 1 : 0

  zone_id = local.route53_zone_id
  name    = local.route53_zone_name
  type    = "A"

  alias {
    name                   = module.alb.alb_dns_name
    zone_id                = module.alb.alb_zone_id
    evaluate_target_health = true
  }
}
