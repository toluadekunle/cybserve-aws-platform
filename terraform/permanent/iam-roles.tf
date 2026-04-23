########################################
# Workspace + CI roles
#
# HCP Terraform roles: one per (workspace, run_phase) pair.
# Plan roles get ReadOnly. Apply roles get AdministratorAccess
# with the workspace permission boundary attached — broad
# within, denied at the audit/IAM user edges.
#
# Per-workspace least-privilege policies are scheduled for
# Phase 2 once the burst-layer resource inventory is final.
# For Phase 1 the permission boundary is the effective
# security control and it's enforced by IAM at evaluation
# time, not by convention.
########################################

locals {
  # Flatten workspace × phase into a map keyed for for_each.
  hcp_role_matrix = merge([
    for ws_name, ws in var.hcp_workspaces : {
      for phase in ws.phases :
      "${ws_name}-${phase}" => {
        workspace = ws_name
        phase     = phase
      }
    }
  ]...)
}

########################################
# HCP workspace assume-role trust policies
########################################
data "aws_iam_policy_document" "hcp_workspace_trust" {
  for_each = local.hcp_role_matrix

  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.hcp.arn]
    }

    # HCP's OIDC token audience claim
    condition {
      test     = "StringEquals"
      variable = "app.terraform.io:aud"
      values   = ["aws.workload.identity"]
    }

    # HCP's sub claim encodes org + workspace + run_phase.
    # This is the binding that makes `hcp-compute-apply`
    # assumable ONLY by the `ha-3tier-compute-prod` workspace
    # during its `apply` phase — nothing else in the org can
    # get these credentials.
    condition {
      test     = "StringEquals"
      variable = "app.terraform.io:sub"
      values = [
        "organization:${var.hcp_organization}:project:*:workspace:${each.value.workspace}:run_phase:${each.value.phase}",
      ]
    }
  }
}

resource "aws_iam_role" "hcp_workspace" {
  for_each = local.hcp_role_matrix

  name                 = "${var.project_name}-hcp-${each.value.workspace}-${each.value.phase}"
  assume_role_policy   = data.aws_iam_policy_document.hcp_workspace_trust[each.key].json
  permissions_boundary = aws_iam_policy.workspace_boundary.arn
  max_session_duration = 3600

  tags = {
    Name      = "${var.project_name}-hcp-${each.value.workspace}-${each.value.phase}"
    Workspace = each.value.workspace
    Phase     = each.value.phase
  }
}

# Plan phases get ReadOnly. This is what any workspace's
# plan step genuinely needs — read the cloud to compute the
# diff. Nothing more.
resource "aws_iam_role_policy_attachment" "hcp_plan_readonly" {
  for_each = { for k, v in local.hcp_role_matrix : k => v if v.phase == "plan" }

  role       = aws_iam_role.hcp_workspace[each.key].name
  policy_arn = "arn:${local.partition}:iam::aws:policy/ReadOnlyAccess"
}

# Apply phases get AdministratorAccess within the permission
# boundary. Effective perms = AdministratorAccess ∩ boundary.
# The boundary's deny block is what makes this defensible.
resource "aws_iam_role_policy_attachment" "hcp_apply_admin" {
  for_each = { for k, v in local.hcp_role_matrix : k => v if v.phase == "apply" }

  role       = aws_iam_role.hcp_workspace[each.key].name
  policy_arn = "arn:${local.partition}:iam::aws:policy/AdministratorAccess"
}

########################################
# GitHub Actions role — Packer AMI builds
#
# Used by the companion app repo's `deploy-app.yml` workflow
# to build AMIs via Packer and write the resulting AMI ID
# to SSM Parameter Store. Nothing else.
########################################
data "aws_iam_policy_document" "github_packer_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values = [
        # Main branch of the platform repo (web-tier AMI)
        "repo:${var.github_org}/${var.github_platform_repo}:ref:refs/heads/main",
        # Main branch of the app repo (app-tier AMI)
        "repo:${var.github_org}/${var.github_app_repo}:ref:refs/heads/main",
      ]
    }
  }
}

data "aws_iam_policy_document" "github_packer" {
  # Packer needs EC2 create/describe + AMI register + snapshot
  # + security-group create (temporary build SG).
  statement {
    sid    = "PackerBuildPermissions"
    effect = "Allow"
    actions = [
      "ec2:AttachVolume",
      "ec2:AuthorizeSecurityGroupIngress",
      "ec2:CopyImage",
      "ec2:CreateImage",
      "ec2:CreateKeypair",
      "ec2:CreateSecurityGroup",
      "ec2:CreateSnapshot",
      "ec2:CreateTags",
      "ec2:CreateVolume",
      "ec2:DeleteKeyPair",
      "ec2:DeleteSecurityGroup",
      "ec2:DeleteSnapshot",
      "ec2:DeleteVolume",
      "ec2:DeregisterImage",
      "ec2:DescribeImageAttribute",
      "ec2:DescribeImages",
      "ec2:DescribeInstances",
      "ec2:DescribeInstanceStatus",
      "ec2:DescribeRegions",
      "ec2:DescribeSecurityGroups",
      "ec2:DescribeSnapshots",
      "ec2:DescribeSubnets",
      "ec2:DescribeTags",
      "ec2:DescribeVolumes",
      "ec2:DetachVolume",
      "ec2:GetPasswordData",
      "ec2:ModifyImageAttribute",
      "ec2:ModifyInstanceAttribute",
      "ec2:ModifySnapshotAttribute",
      "ec2:RegisterImage",
      "ec2:RunInstances",
      "ec2:StopInstances",
      "ec2:TerminateInstances",
    ]
    resources = ["*"]
  }

  # SSM — Packer connects via Session Manager, and writes the
  # resulting AMI ID to a parameter.
  statement {
    sid    = "PackerSessionManager"
    effect = "Allow"
    actions = [
      "ssm:StartSession",
      "ssm:DescribeSessions",
      "ssm:TerminateSession",
      "ssm:GetParameter",
      "ssm:GetParameters",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "WriteAmiPointer"
    effect = "Allow"
    actions = [
      "ssm:PutParameter",
      "ssm:AddTagsToResource",
    ]
    resources = [
      "arn:${local.partition}:ssm:${var.aws_region}:${local.account_id}:parameter/${var.project_name}/*/web-ami-id",
      "arn:${local.partition}:ssm:${var.aws_region}:${local.account_id}:parameter/${var.project_name}/*/app-ami-id",
    ]
  }

  # IAM pass for the Packer instance profile (for SSM agent)
  statement {
    sid     = "PassPackerInstanceProfile"
    effect  = "Allow"
    actions = ["iam:PassRole"]
    resources = [
      "arn:${local.partition}:iam::${local.account_id}:role/${var.project_name}-packer-build",
    ]
  }
}

resource "aws_iam_role" "github_packer" {
  name                 = "${var.project_name}-github-packer"
  assume_role_policy   = data.aws_iam_policy_document.github_packer_trust.json
  permissions_boundary = aws_iam_policy.workspace_boundary.arn
  max_session_duration = 3600

  tags = { Name = "${var.project_name}-github-packer" }
}

resource "aws_iam_role_policy" "github_packer" {
  name   = "${var.project_name}-github-packer"
  role   = aws_iam_role.github_packer.id
  policy = data.aws_iam_policy_document.github_packer.json
}

########################################
# EC2 instance profile for Packer-built instances
# (so the SSM agent on a build instance can connect back)
########################################
data "aws_iam_policy_document" "packer_instance_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "packer_instance" {
  name               = "${var.project_name}-packer-build"
  assume_role_policy = data.aws_iam_policy_document.packer_instance_assume.json

  tags = { Name = "${var.project_name}-packer-build" }
}

resource "aws_iam_role_policy_attachment" "packer_ssm" {
  role       = aws_iam_role.packer_instance.name
  policy_arn = "arn:${local.partition}:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "packer_instance" {
  name = "${var.project_name}-packer-build"
  role = aws_iam_role.packer_instance.name
}

########################################
# Break-glass human role
#
# Assumable only with MFA. Every assume is logged by
# CloudTrail and fires the "root/privileged use" alarm.
# Trust policy restricts to a designated IAM identity —
# bootstrapped as a placeholder; update principal ARN after
# you configure IAM Identity Center / SSO.
########################################
data "aws_iam_policy_document" "breakglass_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type = "AWS"
      # Account root — means ANY identity in this account that
      # has iam:AssumeRole on this role can assume it. Combined
      # with the MFA condition, this is the bootstrap form.
      # Replace with specific IAM Identity Center ARN once SSO
      # is wired.
      identifiers = [local.root_arn]
    }

    condition {
      test     = "Bool"
      variable = "aws:MultiFactorAuthPresent"
      values   = ["true"]
    }

    condition {
      test     = "NumericLessThan"
      variable = "aws:MultiFactorAuthAge"
      values   = ["3600"]
    }
  }
}

resource "aws_iam_role" "breakglass_admin" {
  name                 = "${var.project_name}-breakglass-admin"
  description          = "Break-glass human admin role. MFA required. Every use fires an alarm."
  assume_role_policy   = data.aws_iam_policy_document.breakglass_trust.json
  permissions_boundary = aws_iam_policy.workspace_boundary.arn
  max_session_duration = 3600

  tags = {
    Name      = "${var.project_name}-breakglass-admin"
    Privilege = "break-glass"
  }
}

resource "aws_iam_role_policy_attachment" "breakglass_admin" {
  role       = aws_iam_role.breakglass_admin.name
  policy_arn = "arn:${local.partition}:iam::aws:policy/AdministratorAccess"
}

# Alarm on break-glass assume. Any time anyone uses this role,
# the CIS unauthorized_api_calls alarm pattern won't catch it
# (it's authorized) — so we have a dedicated filter.
resource "aws_cloudwatch_log_metric_filter" "breakglass_use" {
  name           = "${var.project_name}-breakglass-use"
  log_group_name = aws_cloudwatch_log_group.cloudtrail.name
  pattern        = "{ ($.eventName = \"AssumeRole\") && ($.requestParameters.roleArn = \"${aws_iam_role.breakglass_admin.arn}\") }"

  metric_transformation {
    name      = "${var.project_name}-breakglass-use"
    namespace = "CISBenchmark"
    value     = "1"
    unit      = "Count"
  }
}

resource "aws_cloudwatch_metric_alarm" "breakglass_use" {
  alarm_name          = "${var.project_name}-breakglass-use"
  alarm_description   = "Break-glass admin role was assumed — investigate"
  namespace           = "CISBenchmark"
  metric_name         = "${var.project_name}-breakglass-use"
  statistic           = "Sum"
  period              = 60
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"

  alarm_actions = [aws_sns_topic.cis_alarms.arn]

  tags = { Name = "${var.project_name}-breakglass-use" }
}
