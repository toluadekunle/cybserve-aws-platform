########################################
# ACM Private CA — short-lived certificate mode
#
# Usage mode: SHORT_LIVED_CERTIFICATE
#   • Issues certs with <= 7-day lifetime
#   • No CRL, no OCSP — revocation is by expiry
#   • £40/mo flat for the CA + $0.001 per certificate issued
#
# This CA is the internal trust anchor for ALB → instance
# and instance → internal-ALB TLS. Burst layer resources
# (Aurora, instances, ALBs) request certs from it at boot
# via the aws_acmpca_certificate data source + ACM private
# cert issuance.
#
# Deletion has a minimum 7-day permanent-deletion window.
# `terraform destroy` on this resource will NOT succeed
# instantly — this is intentional. The CA persists across
# demo destroy/rebuild cycles.
########################################

resource "aws_acmpca_certificate_authority" "internal" {
  usage_mode = "SHORT_LIVED_CERTIFICATE"
  type       = "ROOT"

  certificate_authority_configuration {
    key_algorithm     = "RSA_4096"
    signing_algorithm = "SHA512WITHRSA"

    subject {
      common_name  = var.private_ca_common_name
      organization = "Cybserve"
      country      = "GB"
    }
  }

  # Revocation disabled — in SHORT_LIVED mode, certs expire
  # fast enough that CRL is unnecessary.
  revocation_configuration {
    crl_configuration {
      enabled = false
    }
    ocsp_configuration {
      enabled = false
    }
  }

  permanent_deletion_time_in_days = 7

  tags = { Name = "${var.project_name}-internal-ca" }
}

########################################
# Self-sign the root
########################################
resource "aws_acmpca_certificate" "internal_root" {
  certificate_authority_arn   = aws_acmpca_certificate_authority.internal.arn
  certificate_signing_request = aws_acmpca_certificate_authority.internal.certificate_signing_request
  signing_algorithm           = "SHA512WITHRSA"
  template_arn                = "arn:${local.partition}:acm-pca:::template/RootCACertificate/V1"

  validity {
    type  = "YEARS"
    value = 10
  }
}

resource "aws_acmpca_certificate_authority_certificate" "internal" {
  certificate_authority_arn = aws_acmpca_certificate_authority.internal.arn
  certificate               = aws_acmpca_certificate.internal_root.certificate
  certificate_chain         = aws_acmpca_certificate.internal_root.certificate_chain
}
