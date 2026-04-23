########################################
# Route53 hosted zones + public ACM certificates
#
# Both zones live in the permanent layer so NS delegation
# from the parent domain (cybserve.co.uk) is a one-time
# configuration. Destroying and rebuilding burst layers
# does NOT rotate NS records.
#
# Public ACM certs are validated via their own zones and
# also live in the permanent layer. Validation takes ~5 min
# on first issue; after that they auto-renew for free and
# the burst layer consumes them by ARN without re-validation.
########################################

########################################
# Prod hosted zone
########################################
resource "aws_route53_zone" "prod" {
  name    = var.primary_domain
  comment = "${var.project_name} prod — delegated from cybserve.co.uk"

  tags = { Name = "${var.project_name}-prod-zone" }
}

########################################
# Staging hosted zone
########################################
resource "aws_route53_zone" "staging" {
  name    = var.staging_domain
  comment = "${var.project_name} staging — delegated from cybserve.co.uk"

  tags = { Name = "${var.project_name}-staging-zone" }
}

########################################
# Public ACM certs — prod
########################################
resource "aws_acm_certificate" "prod" {
  domain_name       = var.primary_domain
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }

  tags = { Name = "${var.project_name}-prod-cert" }
}

resource "aws_route53_record" "prod_cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.prod.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
  zone_id         = aws_route53_zone.prod.zone_id
}

resource "aws_acm_certificate_validation" "prod" {
  certificate_arn         = aws_acm_certificate.prod.arn
  validation_record_fqdns = [for r in aws_route53_record.prod_cert_validation : r.fqdn]
}

########################################
# Public ACM certs — staging
########################################
resource "aws_acm_certificate" "staging" {
  domain_name       = var.staging_domain
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }

  tags = { Name = "${var.project_name}-staging-cert" }
}

resource "aws_route53_record" "staging_cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.staging.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
  zone_id         = aws_route53_zone.staging.zone_id
}

resource "aws_acm_certificate_validation" "staging" {
  certificate_arn         = aws_acm_certificate.staging.arn
  validation_record_fqdns = [for r in aws_route53_record.staging_cert_validation : r.fqdn]
}
