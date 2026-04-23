########################################
# AWS Config
#
# Records all supported resources + global resources (IAM,
# etc.) to the Config history bucket. Rule evaluation is
# continuous. Findings flow into Security Hub automatically
# via the Security Hub → Config integration.
########################################

data "aws_iam_policy_document" "config_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["config.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "config" {
  name               = "${var.project_name}-config-recorder"
  assume_role_policy = data.aws_iam_policy_document.config_assume.json

  tags = { Name = "${var.project_name}-config-recorder" }
}

resource "aws_iam_role_policy_attachment" "config_managed" {
  role       = aws_iam_role.config.name
  policy_arn = "arn:${local.partition}:iam::aws:policy/service-role/AWS_ConfigRole"
}

# Config needs explicit permission to write to our encrypted
# bucket + use the Config CMK.
data "aws_iam_policy_document" "config_delivery" {
  statement {
    effect = "Allow"
    actions = [
      "s3:PutObject",
      "s3:GetBucketAcl",
    ]
    resources = [
      aws_s3_bucket.config.arn,
      "${aws_s3_bucket.config.arn}/*",
    ]
  }

  statement {
    effect = "Allow"
    actions = [
      "kms:GenerateDataKey",
      "kms:Decrypt",
      "kms:DescribeKey",
    ]
    resources = [aws_kms_key.config.arn]
  }
}

resource "aws_iam_role_policy" "config_delivery" {
  name   = "${var.project_name}-config-delivery"
  role   = aws_iam_role.config.id
  policy = data.aws_iam_policy_document.config_delivery.json
}

resource "aws_config_configuration_recorder" "main" {
  name     = "${var.project_name}-recorder"
  role_arn = aws_iam_role.config.arn

  recording_group {
    all_supported                 = true
    include_global_resource_types = true
  }

  depends_on = [aws_iam_role_policy.config_delivery]
}

resource "aws_config_delivery_channel" "main" {
  name           = "${var.project_name}-delivery"
  s3_bucket_name = aws_s3_bucket.config.id
  s3_kms_key_arn = aws_kms_key.config.arn

  snapshot_delivery_properties {
    delivery_frequency = "Six_Hours"
  }

  depends_on = [
    aws_config_configuration_recorder.main,
    aws_s3_bucket_policy.config,
  ]
}

resource "aws_config_configuration_recorder_status" "main" {
  name       = aws_config_configuration_recorder.main.name
  is_enabled = true

  depends_on = [aws_config_delivery_channel.main]
}

########################################
# Config managed rules — the high-value subset.
# (Security Hub brings hundreds more via its CIS/AFSBP
# subscriptions. This block covers rules that Security Hub
# does NOT auto-deploy but that we explicitly want to see
# evaluated even without Security Hub running.)
########################################

locals {
  config_managed_rules = {
    root-account-mfa-enabled      = "ROOT_ACCOUNT_MFA_ENABLED"
    iam-password-policy           = "IAM_PASSWORD_POLICY"
    iam-user-no-policies-check    = "IAM_USER_NO_POLICIES_CHECK"
    iam-user-unused-credentials   = "IAM_USER_UNUSED_CREDENTIALS_CHECK"
    access-keys-rotated           = "ACCESS_KEYS_ROTATED"
    s3-bucket-public-read         = "S3_BUCKET_PUBLIC_READ_PROHIBITED"
    s3-bucket-public-write        = "S3_BUCKET_PUBLIC_WRITE_PROHIBITED"
    s3-bucket-ssl-requests-only   = "S3_BUCKET_SSL_REQUESTS_ONLY"
    s3-bucket-versioning          = "S3_BUCKET_VERSIONING_ENABLED"
    s3-bucket-server-side-enc     = "S3_BUCKET_SERVER_SIDE_ENCRYPTION_ENABLED"
    rds-storage-encrypted         = "RDS_STORAGE_ENCRYPTED"
    rds-instance-public-access    = "RDS_INSTANCE_PUBLIC_ACCESS_CHECK"
    rds-multi-az                  = "RDS_MULTI_AZ_SUPPORT"
    encrypted-volumes             = "ENCRYPTED_VOLUMES"
    ebs-encryption-by-default     = "EC2_EBS_ENCRYPTION_BY_DEFAULT"
    ec2-imdsv2-check              = "EC2_IMDSV2_CHECK"
    ec2-no-public-ip              = "EC2_INSTANCE_NO_PUBLIC_IP"
    vpc-default-sg-closed         = "VPC_DEFAULT_SECURITY_GROUP_CLOSED"
    vpc-sg-open-only-to-auth      = "VPC_SG_OPEN_ONLY_TO_AUTHORIZED_PORTS"
    cloudtrail-enabled            = "CLOUD_TRAIL_ENABLED"
    cloudtrail-encryption         = "CLOUD_TRAIL_ENCRYPTION_ENABLED"
    cloudtrail-log-validation     = "CLOUD_TRAIL_LOG_FILE_VALIDATION_ENABLED"
    cmk-backing-key-rotated       = "CMK_BACKING_KEY_ROTATION_ENABLED"
    guardduty-enabled-centralized = "GUARDDUTY_ENABLED_CENTRALIZED"
    securityhub-enabled           = "SECURITYHUB_ENABLED"
  }

  config_managed_rules_with_input = {
    required-tags = {
      source_identifier = "REQUIRED_TAGS"
      input_parameters = jsonencode({
        tag1Key = "Project"
        tag2Key = "Environment"
        tag3Key = "ManagedBy"
        tag4Key = "Owner"
      })
    }
    access-keys-rotated-90 = {
      source_identifier = "ACCESS_KEYS_ROTATED"
      input_parameters = jsonencode({
        maxAccessKeyAge = "90"
      })
    }
  }
}

resource "aws_config_config_rule" "managed" {
  for_each = local.config_managed_rules

  name = "${var.project_name}-${each.key}"

  source {
    owner             = "AWS"
    source_identifier = each.value
  }

  depends_on = [aws_config_configuration_recorder_status.main]

  tags = { Name = "${var.project_name}-${each.key}" }
}

resource "aws_config_config_rule" "managed_with_input" {
  for_each = local.config_managed_rules_with_input

  name             = "${var.project_name}-${each.key}"
  input_parameters = each.value.input_parameters

  source {
    owner             = "AWS"
    source_identifier = each.value.source_identifier
  }

  depends_on = [aws_config_configuration_recorder_status.main]

  tags = { Name = "${var.project_name}-${each.key}" }
}
