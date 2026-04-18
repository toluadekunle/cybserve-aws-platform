########################################
# Access log bucket
# - If access_log_bucket_id is set (from shared workspace),
#   use it directly. No new bucket, no new policy.
# - Otherwise, fall back to creating a local bucket so the
#   module is still usable standalone.
########################################
locals {
  create_log_bucket = var.access_log_bucket_id == ""
  log_bucket_id     = local.create_log_bucket ? aws_s3_bucket.alb_logs[0].id : var.access_log_bucket_id
}

data "aws_elb_service_account" "main" {
  count = local.create_log_bucket ? 1 : 0
}

resource "random_id" "alb_logs" {
  count       = local.create_log_bucket ? 1 : 0
  byte_length = 4
}

resource "aws_s3_bucket" "alb_logs" {
  count         = local.create_log_bucket ? 1 : 0
  bucket        = "${var.project_name}-${var.environment}-alb-logs-${random_id.alb_logs[0].hex}"
  force_destroy = true # module-owned bucket is disposable

  tags = { Name = "${var.project_name}-${var.environment}-alb-logs" }
}

resource "aws_s3_bucket_policy" "alb_logs" {
  count  = local.create_log_bucket ? 1 : 0
  bucket = aws_s3_bucket.alb_logs[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { AWS = data.aws_elb_service_account.main[0].arn }
      Action    = "s3:PutObject"
      Resource  = "${aws_s3_bucket.alb_logs[0].arn}/*"
    }]
  })
}

########################################
# External ALB (public)
########################################
resource "aws_lb" "external" {
  name               = "${var.project_name}-${var.environment}-ext-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [var.alb_sg_id]
  subnets            = var.public_subnet_ids

  enable_deletion_protection = false
  drop_invalid_header_fields = true

  access_logs {
    bucket  = local.log_bucket_id
    prefix  = "ext-alb"
    enabled = true
  }

  tags = { Name = "${var.project_name}-${var.environment}-ext-alb" }
}

########################################
# Web target group
########################################
resource "aws_lb_target_group" "web" {
  name        = "${var.project_name}-${var.environment}-web-tg"
  port        = var.web_target_port
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "instance"

  health_check {
    enabled             = true
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 30
    path                = var.web_health_path
    matcher             = "200"
  }

  tags = { Name = "${var.project_name}-${var.environment}-web-tg" }
}

########################################
# Listeners: HTTP (redirects to HTTPS) + HTTPS
########################################
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.external.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = var.certificate_arn != "" ? "redirect" : "forward"

    dynamic "redirect" {
      for_each = var.certificate_arn != "" ? [1] : []
      content {
        port        = "443"
        protocol    = "HTTPS"
        status_code = "HTTP_301"
      }
    }

    dynamic "forward" {
      for_each = var.certificate_arn == "" ? [1] : []
      content {
        target_group {
          arn = aws_lb_target_group.web.arn
        }
      }
    }
  }
}

resource "aws_lb_listener" "https" {
  count             = var.certificate_arn != "" ? 1 : 0
  load_balancer_arn = aws_lb.external.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = var.certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.web.arn
  }
}

########################################
# Internal ALB (private) — fronts app tier
########################################
resource "aws_lb" "internal" {
  name               = "${var.project_name}-${var.environment}-int-alb"
  internal           = true
  load_balancer_type = "application"
  security_groups    = [var.int_alb_sg_id]
  subnets            = var.private_subnet_ids

  enable_deletion_protection = false
  drop_invalid_header_fields = true

  access_logs {
    bucket  = local.log_bucket_id
    prefix  = "int-alb"
    enabled = true
  }

  tags = { Name = "${var.project_name}-${var.environment}-int-alb" }
}

resource "aws_lb_target_group" "app" {
  name        = "${var.project_name}-${var.environment}-app-tg"
  port        = var.app_target_port
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "instance"

  health_check {
    enabled             = true
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 30
    path                = var.app_health_path
    matcher             = "200"
  }

  tags = { Name = "${var.project_name}-${var.environment}-app-tg" }
}

resource "aws_lb_listener" "app" {
  load_balancer_arn = aws_lb.internal.arn
  port              = var.app_target_port
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}
