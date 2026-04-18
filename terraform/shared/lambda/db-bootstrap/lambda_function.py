"""
DB bootstrap Lambda.

Idempotent: safe to run on every terraform apply.

Reads:
  MASTER_SECRET_ARN   master credentials (bootstrap use only)
  APP_SECRET_ARN      application user credentials
  DB_NAME             the database the app user should be scoped to

Actions (all idempotent):
  1. CREATE DATABASE IF NOT EXISTS
  2. CREATE USER IF NOT EXISTS using app_user password from APP_SECRET
  3. ALTER USER to force password reconciliation (keeps the secret as source of truth)
  4. GRANT SELECT, INSERT, UPDATE, DELETE on DB.* to app_user
  5. FLUSH PRIVILEGES

Returns a small JSON report the Terraform data source can surface.
"""
import json
import logging
import os

import boto3
import pymysql

log = logging.getLogger()
log.setLevel(logging.INFO)

_secrets = boto3.client("secretsmanager")


def _get_secret(arn: str) -> dict:
    resp = _secrets.get_secret_value(SecretId=arn)
    return json.loads(resp["SecretString"])


def handler(event, _context):
    master_arn = os.environ["MASTER_SECRET_ARN"]
    app_arn = os.environ["APP_SECRET_ARN"]
    db_name = os.environ["DB_NAME"]

    master = _get_secret(master_arn)
    app = _get_secret(app_arn)

    log.info(
        "Connecting as master user '%s' to %s:%s",
        master["username"], master["host"], master["port"],
    )

    conn = pymysql.connect(
        host=master["host"],
        port=int(master["port"]),
        user=master["username"],
        password=master["password"],
        connect_timeout=10,
        autocommit=True,
    )

    try:
        with conn.cursor() as cur:
            cur.execute(f"CREATE DATABASE IF NOT EXISTS `{db_name}` "
                        f"CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;")

            # CREATE USER IF NOT EXISTS requires MySQL 5.7+ / MariaDB 10.1+
            # App user scoped to '%' — RDS does not need host pinning because
            # network-layer isolation (SG + private subnets) already constrains
            # where connections can originate.
            cur.execute(
                "CREATE USER IF NOT EXISTS %s@'%%' IDENTIFIED BY %s;",
                (app["username"], app["password"]),
            )

            # Reconcile password to the current secret value on every run.
            cur.execute(
                "ALTER USER %s@'%%' IDENTIFIED BY %s;",
                (app["username"], app["password"]),
            )

            cur.execute(
                f"GRANT SELECT, INSERT, UPDATE, DELETE "
                f"ON `{db_name}`.* TO %s@'%%';",
                (app["username"],),
            )

            cur.execute("FLUSH PRIVILEGES;")

            # Sanity check — the user exists and can read its grants
            cur.execute("SHOW GRANTS FOR %s@'%%';", (app["username"],))
            grants = [row[0] for row in cur.fetchall()]

        return {
            "status": "ok",
            "database": db_name,
            "app_user": app["username"],
            "grants": grants,
        }
    finally:
        conn.close()
