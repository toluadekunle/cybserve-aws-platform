########################################
# Security group chain
#
# Port contract (kept explicit to eliminate ambiguity):
#
#   Internet
#      ↓  80, 443
#   alb_sg        (external ALB)
#      ↓  web_listen_port (80)
#   web_sg        (Nginx)
#      ↓  app_listen_port (5000)
#   int_alb_sg    (internal ALB)
#      ↓  app_listen_port (5000)
#   app_sg        (Flask)
#      ↓  db_port (3306)
#   rds_sg        (MariaDB)
#
# No SSH. Session Manager via VPC endpoints only.
# Health checks travel the same path as normal traffic.
########################################

# ── External ALB SG ───────────────────────────────────────
resource "aws_security_group" "alb" {
  name_prefix = "${var.project_name}-${var.environment}-alb-"
  description = "External ALB: public HTTP/HTTPS ingress"
  vpc_id      = var.vpc_id

  dynamic "ingress" {
    for_each = var.alb_listen_ports
    content {
      description = "Public ingress on port ${ingress.value}"
      from_port   = ingress.value
      to_port     = ingress.value
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
    }
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project_name}-${var.environment}-alb-sg" }
}

# ── Web tier SG ───────────────────────────────────────────
resource "aws_security_group" "web" {
  name_prefix = "${var.project_name}-${var.environment}-web-"
  description = "Web tier (Nginx): ingress from external ALB only"
  vpc_id      = var.vpc_id

  ingress {
    description     = "From external ALB on web_listen_port"
    from_port       = var.web_listen_port
    to_port         = var.web_listen_port
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project_name}-${var.environment}-web-sg" }
}

# ── Internal ALB SG ───────────────────────────────────────
resource "aws_security_group" "int_alb" {
  name_prefix = "${var.project_name}-${var.environment}-int-alb-"
  description = "Internal ALB: ingress from web tier only"
  vpc_id      = var.vpc_id

  ingress {
    description     = "From web tier on app_listen_port"
    from_port       = var.app_listen_port
    to_port         = var.app_listen_port
    protocol        = "tcp"
    security_groups = [aws_security_group.web.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project_name}-${var.environment}-int-alb-sg" }
}

# ── App tier SG ───────────────────────────────────────────
# Ingress from int_alb only (NOT web directly).
resource "aws_security_group" "app" {
  name_prefix = "${var.project_name}-${var.environment}-app-"
  description = "App tier (Flask): ingress from internal ALB only"
  vpc_id      = var.vpc_id

  ingress {
    description     = "From internal ALB on app_listen_port"
    from_port       = var.app_listen_port
    to_port         = var.app_listen_port
    protocol        = "tcp"
    security_groups = [aws_security_group.int_alb.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project_name}-${var.environment}-app-sg" }
}

# ── RDS SG ────────────────────────────────────────────────
# Ingress from app tier only. The bootstrap Lambda SG is
# added as a separate SG rule by shared/db_bootstrap.tf —
# keeping that out of this module so it stays reusable.
resource "aws_security_group" "rds" {
  name_prefix = "${var.project_name}-${var.environment}-rds-"
  description = "RDS: ingress from app tier only"
  vpc_id      = var.vpc_id

  ingress {
    description     = "From app tier on db_port"
    from_port       = var.db_port
    to_port         = var.db_port
    protocol        = "tcp"
    security_groups = [aws_security_group.app.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project_name}-${var.environment}-rds-sg" }
}
