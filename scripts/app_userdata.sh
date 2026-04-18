#!/bin/bash
set -euxo pipefail

# ─────────────────────────────────────────────────────────
# App tier runtime configuration.
# All OS-level setup is baked into the Packer AMI — this
# script only writes runtime config and starts the service.
# ─────────────────────────────────────────────────────────

# Template variables (rendered by Terraform):
#   ${db_endpoint}   RDS host (no port)
#   ${db_name}       database name
#   ${db_user}       app_user (NOT master)
#   ${db_secret_id}  Secrets Manager secret ID for app_user
#   ${environment}   prod | staging | dev
#   ${aws_region}    AWS region

export DB_ENDPOINT="${db_endpoint}"
export DB_NAME="${db_name}"
export DB_USER="${db_user}"
export DB_SECRET_ID="${DB_SECRET_ID}"
export AWS_REGION="${AWS_REGION}"
export ENVIRONMENT="${environment}"

# Write runtime config for the Flask app.
# The app reads DB_SECRET_ID and fetches the app_user
# password from Secrets Manager at startup via boto3.
# Master credentials are never touched by this tier.
cat > /etc/ha3tier/app.env <<EOF
DB_ENDPOINT=${db_endpoint}
DB_NAME=${db_name}
DB_USER=${db_user}
DB_SECRET_ID=${DB_SECRET_ID}
AWS_REGION=${AWS_REGION}
ENVIRONMENT=${environment}
APP_TIER=app
EOF

chmod 640 /etc/ha3tier/app.env
chown root:ha3tier /etc/ha3tier/app.env

# Smoke check — confirm app_user secret is reachable before
# systemd starts the app. If this fails the instance never
# reaches InService, surfacing the problem immediately.
aws secretsmanager get-secret-value \
  --region "${AWS_REGION}" \
  --secret-id "${DB_SECRET_ID}" \
  --query SecretString \
  --output text > /dev/null

systemctl daemon-reload
systemctl enable --now ha3tier-app.service
