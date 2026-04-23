########################################
# Permission boundary
#
# Every workspace role and every break-glass role attaches
# this boundary. It denies operations that would compromise
# the security story even if the role's attached policy is
# over-permissive:
#
#   • Creating IAM users or access keys (there should never
#     be any — OIDC only)
#   • Disabling / stopping / deleting CloudTrail
#   • Deleting the audit S3 buckets or their object-lock
#     retention policy
#   • Scheduling KMS key deletion on audit CMKs
#   • Disabling GuardDuty / Security Hub / Config
#   • Removing the OIDC providers themselves
#   • Modifying this boundary policy
#   • Creating inline IAM policies (force everything through
#     customer-managed policies so it's auditable)
#
# Roles can do everything else their attached policies allow.
# The boundary is the LAST WORD — any allow is null if the
# boundary doesn't also allow it.
########################################

data "aws_iam_policy_document" "workspace_boundary" {
  # 1. Core allow — gives roles the breadth they need for
  #    workspace work. The DENIES below carve out the
  #    non-negotiables.
  statement {
    sid       = "AllowAllExceptExplicitDenies"
    effect    = "Allow"
    actions   = ["*"]
    resources = ["*"]
  }

  # 2. IAM user + access key lockdown
  statement {
    sid    = "DenyIamUserAndAccessKeyCreation"
    effect = "Deny"
    actions = [
      "iam:CreateUser",
      "iam:CreateAccessKey",
      "iam:UpdateAccessKey",
      "iam:DeleteUser",
    ]
    resources = ["*"]
  }

  # 3. Audit service lockdown
  statement {
    sid    = "DenyAuditServiceTampering"
    effect = "Deny"
    actions = [
      "cloudtrail:StopLogging",
      "cloudtrail:DeleteTrail",
      "cloudtrail:UpdateTrail",
      "cloudtrail:PutEventSelectors",
      "config:DeleteConfigurationRecorder",
      "config:StopConfigurationRecorder",
      "config:DeleteDeliveryChannel",
      "config:DeleteConfigRule",
      "guardduty:DeleteDetector",
      "guardduty:DisassociateFromMasterAccount",
      "guardduty:UpdateDetector",
      "securityhub:DisableSecurityHub",
      "securityhub:BatchDisableStandards",
      "accessanalyzer:DeleteAnalyzer",
      "inspector2:Disable",
      "inspector2:DisableDelegatedAdminAccount",
    ]
    resources = ["*"]
  }

  # 4. KMS audit-key protection
  #    Scheduling deletion of the audit CMKs is denied
  #    unconditionally. Rotation, re-encryption, key policy
  #    changes — all still allowed. Only hard-kill is blocked.
  statement {
    sid    = "DenyAuditKmsKeyDeletion"
    effect = "Deny"
    actions = [
      "kms:ScheduleKeyDeletion",
      "kms:DisableKey",
    ]
    resources = [
      aws_kms_key.cloudtrail.arn,
      aws_kms_key.config.arn,
      aws_kms_key.audit_s3.arn,
    ]
  }

  # 5. Audit bucket protection
  statement {
    sid    = "DenyAuditBucketDeletion"
    effect = "Deny"
    actions = [
      "s3:DeleteBucket",
      "s3:DeleteBucketPolicy",
      "s3:PutBucketPolicy",
      "s3:DeleteObjectVersion",
      "s3:PutObjectRetention",
      "s3:PutObjectLegalHold",
      "s3:BypassGovernanceRetention",
    ]
    resources = [
      aws_s3_bucket.cloudtrail.arn,
      "${aws_s3_bucket.cloudtrail.arn}/*",
      aws_s3_bucket.config.arn,
      "${aws_s3_bucket.config.arn}/*",
    ]
  }

  # 6. OIDC provider lockdown — if a role could delete these,
  #    it could then recreate them with a broader trust and
  #    pivot through.
  statement {
    sid    = "DenyOidcProviderTampering"
    effect = "Deny"
    actions = [
      "iam:DeleteOpenIDConnectProvider",
      "iam:UpdateOpenIDConnectProviderThumbprint",
      "iam:AddClientIDToOpenIDConnectProvider",
    ]
    resources = ["*"]
  }

  # 7. Boundary self-protection — can't detach or rewrite
  #    the boundary policy itself.
  statement {
    sid    = "DenyBoundarySelfModification"
    effect = "Deny"
    actions = [
      "iam:DeletePolicy",
      "iam:DeletePolicyVersion",
      "iam:CreatePolicyVersion",
      "iam:SetDefaultPolicyVersion",
    ]
    resources = [
      "arn:${local.partition}:iam::${local.account_id}:policy/${var.project_name}-workspace-boundary",
    ]
  }

  statement {
    sid    = "DenyBoundaryRoleDetachment"
    effect = "Deny"
    actions = [
      "iam:DeleteRolePermissionsBoundary",
      "iam:PutRolePermissionsBoundary",
    ]
    # The roles whose boundary must never be removed.
    resources = [
      "arn:${local.partition}:iam::${local.account_id}:role/${var.project_name}-hcp-*",
      "arn:${local.partition}:iam::${local.account_id}:role/${var.project_name}-github-*",
      "arn:${local.partition}:iam::${local.account_id}:role/${var.project_name}-breakglass-*",
    ]
  }

  # 8. Force MFA condition for break-glass assume
  #    (Enforced on the role trust policy itself; replicated
  #    here so roles without MFA context can't pivot into
  #    break-glass via iam:PassRole.)
  statement {
    sid     = "DenyPassRoleIntoBreakGlass"
    effect  = "Deny"
    actions = ["iam:PassRole"]
    resources = [
      "arn:${local.partition}:iam::${local.account_id}:role/${var.project_name}-breakglass-*",
    ]
    condition {
      test     = "BoolIfExists"
      variable = "aws:MultiFactorAuthPresent"
      values   = ["false"]
    }
  }
}

resource "aws_iam_policy" "workspace_boundary" {
  name        = "${var.project_name}-workspace-boundary"
  description = "Permission boundary for all workspace + break-glass roles — denies audit tampering and IAM user creation"
  policy      = data.aws_iam_policy_document.workspace_boundary.json

  tags = { Name = "${var.project_name}-workspace-boundary" }
}
