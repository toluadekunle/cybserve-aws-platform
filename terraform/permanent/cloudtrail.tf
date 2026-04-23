########################################
# CloudTrail
#
# Single multi-region trail capturing management events
# plus S3 + Lambda data events. Log files go to the locked
# CloudTrail bucket and are also streamed to a KMS-encrypted
# CloudWatch log group for near-real-time visibility + metric
# filter alarms.
#
# Log file validation is on so tampering with delivered logs
# in S3 is detectable via `aws cloudtrail validate-logs`.
########################################

resource "aws_cloudwatch_log_group" "cloudtrail" {
  name              = "/aws/cloudtrail/${var.project_name}"
  retention_in_days = 90
  kms_key_id        = aws_kms_key.cloudtrail.arn

  tags = { Name = "${var.project_name}-cloudtrail-logs" }
}

data "aws_iam_policy_document" "cloudtrail_to_cwl_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "cloudtrail_to_cwl" {
  name               = "${var.project_name}-cloudtrail-to-cwl"
  assume_role_policy = data.aws_iam_policy_document.cloudtrail_to_cwl_assume.json

  tags = { Name = "${var.project_name}-cloudtrail-to-cwl" }
}

data "aws_iam_policy_document" "cloudtrail_to_cwl" {
  statement {
    effect = "Allow"
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]
    resources = ["${aws_cloudwatch_log_group.cloudtrail.arn}:*"]
  }
}

resource "aws_iam_role_policy" "cloudtrail_to_cwl" {
  name   = "${var.project_name}-cloudtrail-to-cwl"
  role   = aws_iam_role.cloudtrail_to_cwl.id
  policy = data.aws_iam_policy_document.cloudtrail_to_cwl.json
}

resource "aws_cloudtrail" "main" {
  name                          = "${var.project_name}-trail"
  s3_bucket_name                = aws_s3_bucket.cloudtrail.id
  is_multi_region_trail         = true
  include_global_service_events = true
  enable_log_file_validation    = true
  kms_key_id                    = aws_kms_key.cloudtrail.arn

  cloud_watch_logs_group_arn = "${aws_cloudwatch_log_group.cloudtrail.arn}:*"
  cloud_watch_logs_role_arn  = aws_iam_role.cloudtrail_to_cwl.arn

  event_selector {
    read_write_type           = "All"
    include_management_events = true

    data_resource {
      type = "AWS::S3::Object"
      # All S3 objects in this account — catches any attempted
      # exfil of the audit buckets themselves.
      values = ["arn:${local.partition}:s3"]
    }

    data_resource {
      type   = "AWS::Lambda::Function"
      values = ["arn:${local.partition}:lambda"]
    }
  }

  insight_selector {
    insight_type = "ApiCallRateInsight"
  }

  insight_selector {
    insight_type = "ApiErrorRateInsight"
  }

  depends_on = [
    aws_s3_bucket_policy.cloudtrail,
  ]

  tags = { Name = "${var.project_name}-trail" }
}

########################################
# CIS-aligned metric filter alarms on CloudTrail log group
# These are the baseline alarms CIS AWS Foundations expects:
#   3.1  Unauthorized API calls
#   3.2  Console sign-in without MFA
#   3.3  Root account usage
#   3.4  IAM policy changes
#   3.5  CloudTrail config changes
#   3.6  Console auth failures
#   3.7  Customer-managed KMS key disable/delete
#   3.8  S3 bucket policy changes
#   3.9  Config changes
#   3.10 SG changes
#   3.11 NACL changes
#   3.12 Network gateway changes
#   3.13 Route table changes
#   3.14 VPC changes
########################################

resource "aws_sns_topic" "cis_alarms" {
  name              = "${var.project_name}-cis-alarms"
  kms_master_key_id = aws_kms_key.cloudwatch_logs.arn

  tags = { Name = "${var.project_name}-cis-alarms" }
}

locals {
  cis_metric_filters = {
    unauthorized_api_calls = {
      pattern = "{ ($.errorCode = \"*UnauthorizedOperation\") || ($.errorCode = \"AccessDenied*\") }"
    }
    console_no_mfa = {
      pattern = "{ ($.eventName = \"ConsoleLogin\") && ($.additionalEventData.MFAUsed != \"Yes\") && ($.userIdentity.type = \"IAMUser\") && ($.responseElements.ConsoleLogin = \"Success\") }"
    }
    root_account_use = {
      pattern = "{ $.userIdentity.type = \"Root\" && $.userIdentity.invokedBy NOT EXISTS && $.eventType != \"AwsServiceEvent\" }"
    }
    iam_policy_changes = {
      pattern = "{ ($.eventName=DeleteGroupPolicy) || ($.eventName=DeleteRolePolicy) || ($.eventName=DeleteUserPolicy) || ($.eventName=PutGroupPolicy) || ($.eventName=PutRolePolicy) || ($.eventName=PutUserPolicy) || ($.eventName=CreatePolicy) || ($.eventName=DeletePolicy) || ($.eventName=CreatePolicyVersion) || ($.eventName=DeletePolicyVersion) || ($.eventName=AttachRolePolicy) || ($.eventName=DetachRolePolicy) || ($.eventName=AttachUserPolicy) || ($.eventName=DetachUserPolicy) || ($.eventName=AttachGroupPolicy) || ($.eventName=DetachGroupPolicy) }"
    }
    cloudtrail_config_changes = {
      pattern = "{ ($.eventName=CreateTrail) || ($.eventName=UpdateTrail) || ($.eventName=DeleteTrail) || ($.eventName=StartLogging) || ($.eventName=StopLogging) }"
    }
    console_auth_failures = {
      pattern = "{ ($.eventName=ConsoleLogin) && ($.errorMessage=\"Failed authentication\") }"
    }
    kms_cmk_disable = {
      pattern = "{ ($.eventSource=kms.amazonaws.com) && (($.eventName=DisableKey) || ($.eventName=ScheduleKeyDeletion)) }"
    }
    s3_bucket_policy_changes = {
      pattern = "{ ($.eventSource=s3.amazonaws.com) && (($.eventName=PutBucketAcl) || ($.eventName=PutBucketPolicy) || ($.eventName=PutBucketCors) || ($.eventName=PutBucketLifecycle) || ($.eventName=PutBucketReplication) || ($.eventName=DeleteBucketPolicy) || ($.eventName=DeleteBucketCors) || ($.eventName=DeleteBucketLifecycle) || ($.eventName=DeleteBucketReplication)) }"
    }
    config_changes = {
      pattern = "{ ($.eventSource=config.amazonaws.com) && (($.eventName=StopConfigurationRecorder) || ($.eventName=DeleteDeliveryChannel) || ($.eventName=PutDeliveryChannel) || ($.eventName=PutConfigurationRecorder)) }"
    }
    sg_changes = {
      pattern = "{ ($.eventName=AuthorizeSecurityGroupIngress) || ($.eventName=AuthorizeSecurityGroupEgress) || ($.eventName=RevokeSecurityGroupIngress) || ($.eventName=RevokeSecurityGroupEgress) || ($.eventName=CreateSecurityGroup) || ($.eventName=DeleteSecurityGroup) }"
    }
    nacl_changes = {
      pattern = "{ ($.eventName=CreateNetworkAcl) || ($.eventName=CreateNetworkAclEntry) || ($.eventName=DeleteNetworkAcl) || ($.eventName=DeleteNetworkAclEntry) || ($.eventName=ReplaceNetworkAclEntry) || ($.eventName=ReplaceNetworkAclAssociation) }"
    }
    network_gateway_changes = {
      pattern = "{ ($.eventName=CreateCustomerGateway) || ($.eventName=DeleteCustomerGateway) || ($.eventName=AttachInternetGateway) || ($.eventName=CreateInternetGateway) || ($.eventName=DeleteInternetGateway) || ($.eventName=DetachInternetGateway) }"
    }
    route_table_changes = {
      pattern = "{ ($.eventName=CreateRoute) || ($.eventName=CreateRouteTable) || ($.eventName=ReplaceRoute) || ($.eventName=ReplaceRouteTableAssociation) || ($.eventName=DeleteRouteTable) || ($.eventName=DeleteRoute) || ($.eventName=DisassociateRouteTable) }"
    }
    vpc_changes = {
      pattern = "{ ($.eventName=CreateVpc) || ($.eventName=DeleteVpc) || ($.eventName=ModifyVpcAttribute) || ($.eventName=AcceptVpcPeeringConnection) || ($.eventName=CreateVpcPeeringConnection) || ($.eventName=DeleteVpcPeeringConnection) || ($.eventName=RejectVpcPeeringConnection) || ($.eventName=AttachClassicLinkVpc) || ($.eventName=DetachClassicLinkVpc) || ($.eventName=DisableVpcClassicLink) || ($.eventName=EnableVpcClassicLink) }"
    }
  }
}

resource "aws_cloudwatch_log_metric_filter" "cis" {
  for_each = local.cis_metric_filters

  name           = "${var.project_name}-${replace(each.key, "_", "-")}"
  log_group_name = aws_cloudwatch_log_group.cloudtrail.name
  pattern        = each.value.pattern

  metric_transformation {
    name      = "${var.project_name}-${each.key}"
    namespace = "CISBenchmark"
    value     = "1"
    unit      = "Count"
  }
}

resource "aws_cloudwatch_metric_alarm" "cis" {
  for_each = local.cis_metric_filters

  alarm_name          = "${var.project_name}-${replace(each.key, "_", "-")}"
  alarm_description   = "CIS AWS Foundations alarm — ${each.key}"
  namespace           = "CISBenchmark"
  metric_name         = "${var.project_name}-${each.key}"
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"

  alarm_actions = [aws_sns_topic.cis_alarms.arn]
  ok_actions    = []

  tags = { Name = "${var.project_name}-${each.key}" }
}
