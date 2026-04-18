########################################
# DB bootstrap Lambda
#
# v2 fix: uses aws_lambda_invocation *resource* (not the
# data source). Data sources evaluate during plan/refresh,
# which would cause side effects on every PR plan run.
# The resource form only runs on apply.
#
# Re-invocation happens when triggers change:
#   • secret versions (rotation)
#   • Lambda code (source hash)
#
# All SQL is idempotent, so re-runs reconcile drift safely.
########################################

# ── 1. Build the deployment package ───────────────────────
# local-exec runs on apply only (not plan). This is fine.
resource "null_resource" "lambda_build" {
  triggers = {
    source_hash = filesha256("${path.module}/lambda/db-bootstrap/lambda_function.py")
  }

  provisioner "local-exec" {
    command = <<-EOT
      set -eu
      cd ${path.module}/lambda/db-bootstrap
      rm -rf build build.zip
      mkdir -p build
      cp lambda_function.py build/
      pip3 install --target build --quiet pymysql
      cd build && zip -qr ../build.zip . && cd ..
    EOT
  }
}

# ── 2. Lambda SG ──────────────────────────────────────────
resource "aws_security_group" "db_bootstrap_lambda" {
  name_prefix = "${var.project_name}-${var.environment}-dbbootstrap-"
  description = "DB bootstrap Lambda — egress to RDS + Secrets endpoint only"
  vpc_id      = module.vpc.vpc_id

  egress {
    description     = "MySQL to RDS"
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [module.security.rds_sg_id]
  }

  egress {
    description     = "HTTPS to Secrets Manager endpoint"
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [aws_security_group.vpce.id]
  }

  tags = { Name = "${var.project_name}-${var.environment}-dbbootstrap-sg" }
}

resource "aws_security_group_rule" "rds_from_bootstrap" {
  type                     = "ingress"
  from_port                = 3306
  to_port                  = 3306
  protocol                 = "tcp"
  security_group_id        = module.security.rds_sg_id
  source_security_group_id = aws_security_group.db_bootstrap_lambda.id
  description              = "DB bootstrap Lambda"
}

resource "aws_security_group_rule" "vpce_from_bootstrap" {
  type                     = "ingress"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  security_group_id        = aws_security_group.vpce.id
  source_security_group_id = aws_security_group.db_bootstrap_lambda.id
  description              = "DB bootstrap Lambda"
}

# ── 3. IAM ────────────────────────────────────────────────
data "aws_iam_policy_document" "lambda_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "db_bootstrap" {
  name_prefix        = "${var.project_name}-${var.environment}-dbbootstrap-"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json

  tags = { Name = "${var.project_name}-${var.environment}-dbbootstrap-role" }
}

resource "aws_iam_role_policy_attachment" "lambda_vpc" {
  role       = aws_iam_role.db_bootstrap.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

resource "aws_iam_role_policy" "db_bootstrap_secrets" {
  name_prefix = "${var.project_name}-${var.environment}-dbbootstrap-secrets-"
  role        = aws_iam_role.db_bootstrap.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = ["secretsmanager:GetSecretValue"]
      Resource = [
        aws_secretsmanager_secret.db_master.arn,
        aws_secretsmanager_secret.db_app.arn,
      ]
    }]
  })
}

# ── 4. Lambda function ────────────────────────────────────
resource "aws_lambda_function" "db_bootstrap" {
  function_name = "${var.project_name}-${var.environment}-db-bootstrap"
  role          = aws_iam_role.db_bootstrap.arn
  handler       = "lambda_function.handler"
  runtime       = "python3.12"
  timeout       = 60
  memory_size   = 256

  filename         = "${path.module}/lambda/db-bootstrap/build.zip"
  source_code_hash = null_resource.lambda_build.triggers.source_hash

  vpc_config {
    subnet_ids         = module.vpc.private_app_subnet_ids
    security_group_ids = [aws_security_group.db_bootstrap_lambda.id]
  }

  environment {
    variables = {
      MASTER_SECRET_ARN = aws_secretsmanager_secret.db_master.arn
      APP_SECRET_ARN    = aws_secretsmanager_secret.db_app.arn
      DB_NAME           = var.db_name
    }
  }

  depends_on = [
    null_resource.lambda_build,
    aws_iam_role_policy.db_bootstrap_secrets,
    aws_iam_role_policy_attachment.lambda_vpc,
    aws_secretsmanager_secret_version.db_master,
    aws_secretsmanager_secret_version.db_app,
    module.rds,
    aws_vpc_endpoint.interface,
  ]

  tags = { Name = "${var.project_name}-${var.environment}-db-bootstrap" }
}

# ── 5. Invocation — RESOURCE, not data source ─────────────
# This is the key v2 fix.
# CREATE_ONLY means: invoke on create, re-invoke on trigger
# change (via replacement), never invoke on destroy.
resource "aws_lambda_invocation" "db_bootstrap" {
  function_name   = aws_lambda_function.db_bootstrap.function_name
  input           = jsonencode({ action = "bootstrap" })
  lifecycle_scope = "CREATE_ONLY"

  triggers = {
    master_secret_version = aws_secretsmanager_secret_version.db_master.version_id
    app_secret_version    = aws_secretsmanager_secret_version.db_app.version_id
    function_code_hash    = null_resource.lambda_build.triggers.source_hash
  }

  depends_on = [aws_lambda_function.db_bootstrap]
}

output "db_bootstrap_result" {
  description = "Most recent Lambda bootstrap result — confirms grants applied"
  value       = jsondecode(aws_lambda_invocation.db_bootstrap.result)
}
