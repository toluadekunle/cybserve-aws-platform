########################################
# Threat detection services
#
# Security Hub (aggregator + CIS + AFSBP standards)
# GuardDuty (detector + all optional data sources)
# Inspector v2 (EC2 + Lambda + container scanning)
# IAM Access Analyzer (account-level)
########################################

########################################
# GuardDuty
########################################
resource "aws_guardduty_detector" "main" {
  enable = true

  datasources {
    s3_logs {
      enable = true
    }
    kubernetes {
      audit_logs {
        enable = false # No EKS in this stack
      }
    }
    malware_protection {
      scan_ec2_instance_with_findings {
        ebs_volumes {
          enable = true
        }
      }
    }
  }

  finding_publishing_frequency = "FIFTEEN_MINUTES"

  tags = { Name = "${var.project_name}-guardduty" }
}

# GuardDuty has additional "feature"-based data sources that
# are enabled via a separate resource in newer provider
# versions. Wire RDS protection, Lambda protection, and
# EKS runtime monitoring (off since no EKS).
resource "aws_guardduty_detector_feature" "rds_protection" {
  detector_id = aws_guardduty_detector.main.id
  name        = "RDS_LOGIN_EVENTS"
  status      = "ENABLED"
}

resource "aws_guardduty_detector_feature" "lambda_protection" {
  detector_id = aws_guardduty_detector.main.id
  name        = "LAMBDA_NETWORK_LOGS"
  status      = "ENABLED"
}

resource "aws_guardduty_detector_feature" "s3_data_events" {
  detector_id = aws_guardduty_detector.main.id
  name        = "S3_DATA_EVENTS"
  status      = "ENABLED"
}

resource "aws_guardduty_detector_feature" "ebs_malware" {
  detector_id = aws_guardduty_detector.main.id
  name        = "EBS_MALWARE_PROTECTION"
  status      = "ENABLED"
}

########################################
# IAM Access Analyzer
########################################
resource "aws_accessanalyzer_analyzer" "account" {
  analyzer_name = "${var.project_name}-account-analyzer"
  type          = "ACCOUNT"

  tags = { Name = "${var.project_name}-account-analyzer" }
}

# Unused-access analyzer flags IAM entities that haven't been
# used in a tracked window — surfaces the "credentials that
# haven't been rotated because nothing uses them" problem.
resource "aws_accessanalyzer_analyzer" "unused_access" {
  analyzer_name = "${var.project_name}-unused-access"
  type          = "ACCOUNT_UNUSED_ACCESS"

  configuration {
    unused_access {
      unused_access_age = 90
    }
  }

  tags = { Name = "${var.project_name}-unused-access" }
}

########################################
# Inspector v2
########################################
resource "aws_inspector2_enabler" "this" {
  account_ids    = [local.account_id]
  resource_types = ["EC2", "LAMBDA", "LAMBDA_CODE"]
}

########################################
# Security Hub
#
# Enables the hub, then subscribes to the two standards we
# want: CIS AWS Foundations Benchmark v1.4.0 and AWS FSBP.
# Findings from Config, GuardDuty, Inspector, and Access
# Analyzer all flow in automatically via the default product
# integrations.
########################################
resource "aws_securityhub_account" "main" {
  enable_default_standards  = false
  auto_enable_controls      = true
  control_finding_generator = "SECURITY_CONTROL"
}

resource "aws_securityhub_standards_subscription" "cis_v140" {
  standards_arn = "arn:${local.partition}:securityhub:${var.aws_region}::standards/cis-aws-foundations-benchmark/v/1.4.0"
  depends_on    = [aws_securityhub_account.main]
}

resource "aws_securityhub_standards_subscription" "afsbp" {
  standards_arn = "arn:${local.partition}:securityhub:${var.aws_region}::standards/aws-foundational-security-best-practices/v/1.0.0"
  depends_on    = [aws_securityhub_account.main]
}

resource "aws_securityhub_standards_subscription" "nist_800_53" {
  standards_arn = "arn:${local.partition}:securityhub:${var.aws_region}::standards/nist-800-53/v/5.0.0"
  depends_on    = [aws_securityhub_account.main]
}
