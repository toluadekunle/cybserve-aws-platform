########################################
# Customer-managed KMS keys for the permanent + state layers.
#
# Design: one CMK per concern. Key policies grant only the
# AWS principals that genuinely need to use the key — never
# `Principal: *` and never unscoped root access for use
# (root keeps admin perms only, which lets us recover from
# policy mistakes without opening the key to workloads).
#
# Rotation is enabled on every key. Deletion window is set
# to the maximum (30 days) so a mistaken destroy is
# recoverable.
########################################

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  partition  = data.aws_partition.current.partition
  root_arn   = "arn:${local.partition}:iam::${local.account_id}:root"
}

########################################
# CMK: CloudTrail logs
########################################
resource "aws_kms_key" "cloudtrail" {
  description             = "Encrypts CloudTrail management + data events in S3 and CloudWatch"
  deletion_window_in_days = 30
  enable_key_rotation     = true
  is_enabled              = true

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "EnableRootAdmin"
        Effect    = "Allow"
        Principal = { AWS = local.root_arn }
        Action    = "kms:*"
        Resource  = "*"
      },
      {
        Sid       = "AllowCloudTrailEncryptDecrypt"
        Effect    = "Allow"
        Principal = { Service = "cloudtrail.amazonaws.com" }
        Action = [
          "kms:GenerateDataKey*",
          "kms:DescribeKey",
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = local.account_id
          }
          StringLike = {
            "kms:EncryptionContext:aws:cloudtrail:arn" = "arn:${local.partition}:cloudtrail:*:${local.account_id}:trail/*"
          }
        }
      },
      {
        Sid       = "AllowCloudTrailDescribe"
        Effect    = "Allow"
        Principal = { Service = "cloudtrail.amazonaws.com" }
        Action    = "kms:DescribeKey"
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
          "kms:DescribeKey",
        ]
        Resource = "*"
        Condition = {
          ArnLike = {
            "kms:EncryptionContext:aws:logs:arn" = "arn:${local.partition}:logs:${var.aws_region}:${local.account_id}:log-group:*"
          }
        }
      },
    ]
  })

  tags = { Name = "${var.project_name}-cloudtrail-cmk" }
}

resource "aws_kms_alias" "cloudtrail" {
  name          = "alias/${var.project_name}-cloudtrail"
  target_key_id = aws_kms_key.cloudtrail.key_id
}

########################################
# CMK: Config recorder + history bucket
########################################
resource "aws_kms_key" "config" {
  description             = "Encrypts AWS Config recorder and history bucket"
  deletion_window_in_days = 30
  enable_key_rotation     = true

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "EnableRootAdmin"
        Effect    = "Allow"
        Principal = { AWS = local.root_arn }
        Action    = "kms:*"
        Resource  = "*"
      },
      {
        Sid       = "AllowConfigUse"
        Effect    = "Allow"
        Principal = { Service = "config.amazonaws.com" }
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey",
          "kms:DescribeKey",
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = local.account_id
          }
        }
      },
    ]
  })

  tags = { Name = "${var.project_name}-config-cmk" }
}

resource "aws_kms_alias" "config" {
  name          = "alias/${var.project_name}-config"
  target_key_id = aws_kms_key.config.key_id
}

########################################
# CMK: generic audit S3 buckets (flow logs, ALB logs)
########################################
resource "aws_kms_key" "audit_s3" {
  description             = "Encrypts VPC flow log archive + ALB access log bucket"
  deletion_window_in_days = 30
  enable_key_rotation     = true

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "EnableRootAdmin"
        Effect    = "Allow"
        Principal = { AWS = local.root_arn }
        Action    = "kms:*"
        Resource  = "*"
      },
      {
        Sid       = "AllowDeliveryLogsService"
        Effect    = "Allow"
        Principal = { Service = "delivery.logs.amazonaws.com" }
        Action = [
          "kms:GenerateDataKey*",
          "kms:Decrypt",
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = local.account_id
          }
        }
      },
    ]
  })

  tags = { Name = "${var.project_name}-audit-s3-cmk" }
}

resource "aws_kms_alias" "audit_s3" {
  name          = "alias/${var.project_name}-audit-s3"
  target_key_id = aws_kms_key.audit_s3.key_id
}

########################################
# CMK: CloudWatch Logs (application + system)
########################################
resource "aws_kms_key" "cloudwatch_logs" {
  description             = "Encrypts CloudWatch log groups used by the burst layer (WAF logs, SSM sessions, app logs)"
  deletion_window_in_days = 30
  enable_key_rotation     = true

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "EnableRootAdmin"
        Effect    = "Allow"
        Principal = { AWS = local.root_arn }
        Action    = "kms:*"
        Resource  = "*"
      },
      {
        Sid       = "AllowCloudWatchLogsUse"
        Effect    = "Allow"
        Principal = { Service = "logs.${var.aws_region}.amazonaws.com" }
        Action = [
          "kms:Encrypt*",
          "kms:Decrypt*",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:Describe*",
        ]
        Resource = "*"
        Condition = {
          ArnLike = {
            "kms:EncryptionContext:aws:logs:arn" = "arn:${local.partition}:logs:${var.aws_region}:${local.account_id}:log-group:*"
          }
        }
      },
    ]
  })

  tags = { Name = "${var.project_name}-cloudwatch-logs-cmk" }
}

resource "aws_kms_alias" "cloudwatch_logs" {
  name          = "alias/${var.project_name}-cloudwatch-logs"
  target_key_id = aws_kms_key.cloudwatch_logs.key_id
}

########################################
# CMK: EBS (default account-level encryption)
########################################
resource "aws_kms_key" "ebs" {
  description             = "Default account-level EBS volume encryption CMK"
  deletion_window_in_days = 30
  enable_key_rotation     = true

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "EnableRootAdmin"
        Effect    = "Allow"
        Principal = { AWS = local.root_arn }
        Action    = "kms:*"
        Resource  = "*"
      },
      {
        Sid       = "AllowAutoScalingUseOfCMK"
        Effect    = "Allow"
        Principal = { AWS = "arn:${local.partition}:iam::${local.account_id}:role/aws-service-role/autoscaling.amazonaws.com/AWSServiceRoleForAutoScaling" }
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:DescribeKey",
          "kms:CreateGrant",
        ]
        Resource = "*"
      },
    ]
  })

  tags = { Name = "${var.project_name}-ebs-cmk" }
}

resource "aws_kms_alias" "ebs" {
  name          = "alias/${var.project_name}-ebs"
  target_key_id = aws_kms_key.ebs.key_id
}

# Set this CMK as the account-region default for new EBS volumes.
# Any EC2/ASG that creates a volume without specifying a key will
# pick this one up automatically.
resource "aws_ebs_default_kms_key" "this" {
  key_arn = aws_kms_key.ebs.arn
}

resource "aws_ebs_encryption_by_default" "this" {
  enabled = true
}

########################################
# CMK: Secrets Manager (shared workspace + burst-layer secrets)
########################################
resource "aws_kms_key" "secrets" {
  description             = "Encrypts Secrets Manager secrets (DB master + app user + any Private CA artifacts)"
  deletion_window_in_days = 30
  enable_key_rotation     = true

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "EnableRootAdmin"
        Effect    = "Allow"
        Principal = { AWS = local.root_arn }
        Action    = "kms:*"
        Resource  = "*"
      },
      {
        Sid       = "AllowSecretsManagerUse"
        Effect    = "Allow"
        Principal = { Service = "secretsmanager.amazonaws.com" }
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey",
          "kms:DescribeKey",
          "kms:CreateGrant",
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = local.account_id
          }
        }
      },
    ]
  })

  tags = { Name = "${var.project_name}-secrets-cmk" }
}

resource "aws_kms_alias" "secrets" {
  name          = "alias/${var.project_name}-secrets"
  target_key_id = aws_kms_key.secrets.key_id
}

########################################
# CMK: RDS / Aurora (cluster storage + automated backups + Backup vault)
########################################
resource "aws_kms_key" "rds" {
  description             = "Encrypts Aurora cluster storage, automated backups, and manual snapshots"
  deletion_window_in_days = 30
  enable_key_rotation     = true

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "EnableRootAdmin"
        Effect    = "Allow"
        Principal = { AWS = local.root_arn }
        Action    = "kms:*"
        Resource  = "*"
      },
      {
        Sid       = "AllowRDSUse"
        Effect    = "Allow"
        Principal = { Service = "rds.amazonaws.com" }
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey",
          "kms:DescribeKey",
          "kms:CreateGrant",
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = local.account_id
          }
        }
      },
      {
        Sid       = "AllowBackupUse"
        Effect    = "Allow"
        Principal = { Service = "backup.amazonaws.com" }
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey",
          "kms:DescribeKey",
          "kms:CreateGrant",
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = local.account_id
          }
        }
      },
    ]
  })

  tags = { Name = "${var.project_name}-rds-cmk" }
}

resource "aws_kms_alias" "rds" {
  name          = "alias/${var.project_name}-rds"
  target_key_id = aws_kms_key.rds.key_id
}
