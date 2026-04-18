#!/bin/bash
set -euxo pipefail

# ─────────────────────────────────────────────────────────
# Web tier runtime configuration.
# No database credentials. No Secrets Manager access.
# Just Nginx pointed at the internal ALB.
# ─────────────────────────────────────────────────────────

# Template variables:
#   ${app_tier_endpoint}  internal ALB DNS
#   ${environment}        prod | staging | dev

export APP_TIER_ENDPOINT="${APP_TIER_ENDPOINT}"
export ENVIRONMENT="${ENVIRONMENT}"

# Write Nginx upstream config. The `resolver` directive
# plus `valid=30s` tells Nginx to re-resolve the ALB DNS
# every 30 seconds — required because the internal ALB
# IP can change and long-lived Nginx workers otherwise
# cache it indefinitely and blackhole traffic.
cat > /etc/nginx/conf.d/app.conf <<EOF
resolver 169.254.169.253 valid=30s ipv6=off;

upstream app_tier {
    server ${app_tier_endpoint}:5000;
}

server {
    listen 80 default_server;
    server_name _;

    location /health {
        access_log off;
        return 200 "ok\n";
        add_header Content-Type text/plain;
    }

    location / {
        set \$upstream_app "${app_tier_endpoint}";
        proxy_pass http://\$upstream_app:5000;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_connect_timeout 5s;
        proxy_read_timeout 30s;
    }
}
EOF

nginx -t
systemctl enable --now nginx
systemctl reload nginx
