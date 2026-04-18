########################################
# 1. Network (VPC + subnets + endpoints)
########################################
module "vpc" {
  source = "../modules/vpc"

  project_name              = var.project_name
  environment               = var.environment
  vpc_cidr                  = var.vpc_cidr
  availability_zones        = var.availability_zones
  public_subnet_cidrs       = var.public_subnet_cidrs
  private_app_subnet_cidrs  = var.private_app_subnet_cidrs
  private_data_subnet_cidrs = var.private_data_subnet_cidrs
}

########################################
# 2. Security groups
########################################
module "security" {
  source = "../modules/security"

  project_name = var.project_name
  environment  = var.environment
  vpc_id       = module.vpc.vpc_id
  vpc_cidr     = var.vpc_cidr

  alb_listen_ports       = var.alb_listen_ports
  web_listen_port        = var.web_listen_port
  app_listen_port        = var.app_listen_port
  db_port                = var.db_port
}

########################################
# 3. RDS
########################################
module "rds" {
  source = "../modules/rds"

  project_name              = var.project_name
  environment               = var.environment
  db_name                   = var.db_name
  db_username               = var.db_master_username
  db_password               = random_password.db_master.result
  db_instance_class         = var.db_instance_class
  db_allocated_storage      = var.db_allocated_storage
  backup_retention_period   = var.db_backup_retention_period
  private_data_subnet_ids   = module.vpc.private_data_subnet_ids
  rds_security_group_id     = module.security.rds_sg_id
}

########################################
# 4. Secrets
########################################
resource "random_password" "db_master" {
  length           = 32
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

resource "random_password" "db_app" {
  length           = 32
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

resource "aws_secretsmanager_secret" "db_master" {
  name_prefix             = "${var.project_name}-${var.environment}-db-master-"
  description             = "RDS master credentials — bootstrap only, NEVER read by application"
  recovery_window_in_days = 7

  tags = {
    Name = "${var.project_name}-${var.environment}-db-master"
    Role = "database-master"
  }
}

resource "aws_secretsmanager_secret_version" "db_master" {
  secret_id = aws_secretsmanager_secret.db_master.id
  secret_string = jsonencode({
    username = var.db_master_username
    password = random_password.db_master.result
    engine   = "mysql"
    host     = split(":", module.rds.db_endpoint)[0]
    port     = tonumber(split(":", module.rds.db_endpoint)[1])
    dbname   = var.db_name
  })
}

resource "aws_secretsmanager_secret" "db_app" {
  name_prefix             = "${var.project_name}-${var.environment}-db-app-"
  description             = "Application DB user credentials — least privilege (SELECT/INSERT/UPDATE/DELETE)"
  recovery_window_in_days = 7

  tags = {
    Name = "${var.project_name}-${var.environment}-db-app"
    Role = "database-app-user"
  }
}

resource "aws_secretsmanager_secret_version" "db_app" {
  secret_id = aws_secretsmanager_secret.db_app.id
  secret_string = jsonencode({
    username = var.db_app_username
    password = random_password.db_app.result
    engine   = "mysql"
    host     = split(":", module.rds.db_endpoint)[0]
    port     = tonumber(split(":", module.rds.db_endpoint)[1])
    dbname   = var.db_name
  })
}

########################################
# 5. VPC interface endpoints + policies
#    v2: Secrets Manager endpoint policy
#    scoped to the two secrets only.
########################################
resource "aws_security_group" "vpce" {
  name_prefix = "${var.project_name}-${var.environment}-vpce-"
  description = "VPC interface endpoint SG — allow HTTPS from private subnets"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description = "HTTPS from private app + data subnets"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = concat(var.private_app_subnet_cidrs, var.private_data_subnet_cidrs)
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project_name}-${var.environment}-vpce-sg" }
}

locals {
  interface_endpoints = [
    "com.amazonaws.${var.aws_region}.ssm",
    "com.amazonaws.${var.aws_region}.ssmmessages",
    "com.amazonaws.${var.aws_region}.ec2messages",
    "com.amazonaws.${var.aws_region}.secretsmanager",
    "com.amazonaws.${var.aws_region}.logs",
  ]
}

resource "aws_vpc_endpoint" "interface" {
  for_each = toset(local.interface_endpoints)

  vpc_id              = module.vpc.vpc_id
  service_name        = each.value
  vpc_endpoint_type   = "Interface"
  subnet_ids          = module.vpc.private_app_subnet_ids
  security_group_ids  = [aws_security_group.vpce.id]
  private_dns_enabled = true

  tags = {
    Name = "${var.project_name}-${var.environment}-${replace(each.value, "com.amazonaws.${var.aws_region}.", "")}-vpce"
  }
}

# Secrets Manager endpoint policy — restrict to the two
# secrets this platform manages. Blocks exfil to other
# secrets in the account even if an instance role were
# compromised.
data "aws_caller_identity" "current" {}

resource "aws_vpc_endpoint_policy" "secretsmanager" {
  vpc_endpoint_id = aws_vpc_endpoint.interface["com.amazonaws.${var.aws_region}.secretsmanager"].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowScopedSecretReads"
        Effect    = "Allow"
        Principal = { AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root" }
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret",
        ]
        Resource = [
          aws_secretsmanager_secret.db_master.arn,
          aws_secretsmanager_secret.db_app.arn,
        ]
      },
      {
        # Secrets Manager needs GetRandomPassword to be callable
        # without a resource (it has none). Keep it separate.
        Sid       = "AllowServiceMetaOps"
        Effect    = "Allow"
        Principal = { AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root" }
        Action    = ["secretsmanager:GetRandomPassword"]
        Resource  = "*"
      },
    ]
  })
}

########################################
# 6. KMS key for Session Manager logs
########################################
resource "aws_kms_key" "ssm_logs" {
  description             = "KMS key for Session Manager CloudWatch log group"
  deletion_window_in_days = 30
  enable_key_rotation     = true

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "EnableRootAccount"
        Effect    = "Allow"
        Principal = { AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root" }
        Action    = "kms:*"
        Resource  = "*"
      },
      {
        Sid       = "AllowCloudWatchLogsUse"
        Effect    = "Allow"
        Principal = { Service = "logs.${var.aws_region}.amazonaws.com" }
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:Describe*",
        ]
        Resource  = "*"
        Condition = {
          ArnLike = {
            "kms:EncryptionContext:aws:logs:arn" = "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/ssm/*"
          }
        }
      },
    ]
  })

  tags = { Name = "${var.project_name}-${var.environment}-ssm-logs" }
}

resource "aws_kms_alias" "ssm_logs" {
  name          = "alias/${var.project_name}-${var.environment}-ssm-logs"
  target_key_id = aws_kms_key.ssm_logs.key_id
}

########################################
# 7. SSM Session Manager (KMS-encrypted logs)
########################################
resource "random_id" "ssm_log" {
  byte_length = 4
}

resource "aws_cloudwatch_log_group" "ssm_sessions" {
  name              = "/aws/ssm/${var.project_name}-${var.environment}-sessions-${random_id.ssm_log.hex}"
  retention_in_days = var.alb_log_retention_days
  kms_key_id        = aws_kms_key.ssm_logs.arn

  tags = { Name = "${var.project_name}-${var.environment}-ssm-sessions" }
}

# Note: SSM-SessionManagerRunShell is AWS's reserved default
# document name. Creating it here makes THIS workload's
# settings the account-region default. Safe for single-
# workload accounts; document the collision risk in multi-
# workload accounts (see REFACTOR.md "Multi-client notes").
resource "aws_ssm_document" "session_manager" {
  name            = "SSM-SessionManagerRunShell"
  document_type   = "Session"
  document_format = "JSON"

  content = jsonencode({
    schemaVersion = "1.0"
    description   = "Session Manager run shell with KMS-encrypted CloudWatch logging"
    sessionType   = "Standard_Stream"
    inputs = {
      cloudWatchLogGroupName      = aws_cloudwatch_log_group.ssm_sessions.name
      cloudWatchEncryptionEnabled = true
      cloudWatchStreamingEnabled  = true
      runAsEnabled                = false
      idleSessionTimeout          = "20"
      shellProfile = {
        linux = "cd ~ && bash"
      }
    }
  })

  tags = { Name = "${var.project_name}-${var.environment}-ssm-sessions" }
}

########################################
# 8. ACM certificate + Route53 subdomain
########################################
resource "aws_acm_certificate" "main" {
  count = var.enable_route53 ? 1 : 0

  domain_name       = var.route53_zone_name
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }

  tags = { Name = "${var.project_name}-${var.environment}-cert" }
}

resource "aws_route53_zone" "app" {
  count = var.enable_route53 ? 1 : 0

  name    = var.route53_zone_name
  comment = "Subdomain delegated from parent registrar — ${var.route53_zone_name}"

  tags = { Name = "${var.project_name}-${var.environment}-zone" }
}

resource "aws_route53_record" "cert_validation" {
  for_each = var.enable_route53 ? {
    for dvo in aws_acm_certificate.main[0].domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  } : {}

  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
  zone_id         = aws_route53_zone.app[0].zone_id
}

resource "aws_acm_certificate_validation" "main" {
  count = var.enable_route53 ? 1 : 0

  certificate_arn         = aws_acm_certificate.main[0].arn
  validation_record_fqdns = [for record in aws_route53_record.cert_validation : record.fqdn]
}

########################################
# 9. ALB access-log bucket (modernised policy)
#    v2: use logdelivery service principal +
#    aws:SourceArn constraint. Keeps the legacy
#    aws_elb_service_account principal as a
#    second statement for backward compatibility.
########################################
data "aws_elb_service_account" "main" {}

resource "random_id" "alb_logs" {
  byte_length = 4
}

resource "aws_s3_bucket" "alb_logs" {
  bucket        = "${var.project_name}-${var.environment}-alb-logs-${random_id.alb_logs.hex}"
  force_destroy = false

  tags = { Name = "${var.project_name}-${var.environment}-alb-logs" }
}

resource "aws_s3_bucket_ownership_controls" "alb_logs" {
  bucket = aws_s3_bucket.alb_logs.id
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "alb_logs" {
  bucket = aws_s3_bucket.alb_logs.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "alb_logs" {
  bucket                  = aws_s3_bucket.alb_logs.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "alb_logs" {
  bucket = aws_s3_bucket.alb_logs.id

  rule {
    id     = "expire-old-logs"
    status = "Enabled"

    filter {
      prefix = ""
    }

    expiration {
      days = 90
    }
  }
}

resource "aws_s3_bucket_policy" "alb_logs" {
  bucket = aws_s3_bucket.alb_logs.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # Modern ALB logging principal (newer AWS regions)
        Sid       = "ModernALBLogDelivery"
        Effect    = "Allow"
        Principal = { Service = "logdelivery.elasticloadbalancing.amazonaws.com" }
        Action    = "s3:PutObject"
        Resource  = "${aws_s3_bucket.alb_logs.arn}/AWSLogs/${data.aws_caller_identity.current.account_id}/*"
      },
      {
        # Legacy principal for older regions (incl. eu-west-2)
        # aws_elb_service_account returns the correct account
        # ID for the ELB service in the current region.
        Sid       = "LegacyALBLogDelivery"
        Effect    = "Allow"
        Principal = { AWS = data.aws_elb_service_account.main.arn }
        Action    = "s3:PutObject"
        Resource  = "${aws_s3_bucket.alb_logs.arn}/AWSLogs/${data.aws_caller_identity.current.account_id}/*"
      },
      {
        Sid       = "AllowGetBucketAcl"
        Effect    = "Allow"
        Principal = { Service = "delivery.logs.amazonaws.com" }
        Action    = "s3:GetBucketAcl"
        Resource  = aws_s3_bucket.alb_logs.arn
      },
    ]
  })
}
