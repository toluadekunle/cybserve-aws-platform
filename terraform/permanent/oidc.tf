########################################
# OIDC identity providers
#
# Two federations into this AWS account:
#   1. GitHub Actions (token.actions.githubusercontent.com)
#      — used by the platform + app CI workflows to assume
#      narrow roles for AMI builds and drill dispatch.
#
#   2. HCP Terraform (app.terraform.io)
#      — used by every Terraform workspace (permanent,
#      shared-prod, compute-prod, shared-staging,
#      compute-staging). Replaces the static IAM user
#      credentials HCP was using.
#
# AWS's STS AssumeRoleWithWebIdentity API handles the rest.
# We never hold long-lived AWS credentials anywhere.
########################################

########################################
# GitHub Actions OIDC
########################################
# Thumbprints: AWS no longer strictly validates these (July 2023
# change — AWS automatically retrieves the thumbprint from the
# OIDC provider's TLS cert). The value is still required by the
# API. Using GitHub's published root + intermediate thumbprints
# as a defense-in-depth belt-and-braces.
resource "aws_iam_openid_connect_provider" "github" {
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
  thumbprint_list = [
    "6938fd4d98bab03faadb97b34396831e3780aea1",
    "1c58a3a8518e8759bf075b76b750d4f2df264fcd",
  ]

  tags = { Name = "${var.project_name}-github-actions" }
}

########################################
# HCP Terraform OIDC
########################################
# HCP publishes its OIDC discovery doc at
# https://app.terraform.io/.well-known/openid-configuration
# and uses `aws.workload.identity` as the audience claim.
data "tls_certificate" "hcp" {
  url = "https://app.terraform.io"
}

resource "aws_iam_openid_connect_provider" "hcp" {
  url             = "https://app.terraform.io"
  client_id_list  = ["aws.workload.identity"]
  thumbprint_list = [data.tls_certificate.hcp.certificates[0].sha1_fingerprint]

  tags = { Name = "${var.project_name}-hcp-terraform" }
}
