# HA 3-tier — client-ready refactor, v3

Third revision. Polish pass on top of v2.

## Changes from v2

| # | Change | Why |
|---|---|---|
| 1 | **Shared outputs trimmed** | Dropped 7 outputs that compute never reads (`vpc_cidr`, `private_data_subnet_ids`, `availability_zones`, `db_master_username`, master secret ARN + ID, `ssm_session_log_group`). Minimises coupling and reduces information exposure. `route53_name_servers` kept for operator visibility. Every output is now tagged "consumed by compute" or "operator visibility only." |
| 2 | **Run trigger documented** | REFACTOR.md Step 4 is now the 30-second UI setup. A codified alternative lives at `terraform/compute/run_trigger.tf.example` for operators who want it under version control (requires TFE_TOKEN setup — full prerequisites in the file header). |
| 3 | **Migration appendix in REFACTOR.md** | Documents the correct `state rm` → `import` order for any future scenario where you migrate from a running workspace. Not needed for this rollout because your stack is destroyed, but future-proofs the playbook. |

## Unchanged from v2

All seven v2 fixes still apply:

- Lambda invocation: `resource` (not data source) with `CREATE_ONLY` + triggers
- Full security module shipped (port chain explicit)
- WAF baseline restored: Common + KnownBadInputs + IpReputationList + RateLimit + logging with redacted headers
- Secrets Manager VPC endpoint policy scoped to the two secrets
- KMS encryption on Session Manager logs
- ALB log bucket policy modernised (`logdelivery.elasticloadbalancing.amazonaws.com` + legacy fallback + ownership controls)
- Shared workspace workflows (`terraform-plan-shared.yml`, `terraform-apply-shared.yml` gated on `shared-prod` environment)

## Unchanged from v1 (original architecture)

- Two-workspace split (`ha-3tier-shared-prod` + `ha-3tier-compute-prod`)
- `tfe_outputs.nonsensitive_values` for cross-workspace reads
- `app_user` separation from master (bootstrap Lambda creates/reconciles)
- Route53 subdomain delegation + ALB A-alias (zero manual DNS on rebuild)
- RDS `lifecycle { prevent_destroy = true }` + `deletion_protection = true`
- Shared-owned ALB log bucket
- `latest_version` on ec2-asg (Error 15 fix)

## Deliberate scope decisions (future work)

Documented in the README + REFACTOR.md Multi-client notes:

- **OIDC for GitHub and HCP** — target state confirmed; not this round
- **Account baseline split** (for SSM document collisions) — only matters at multi-workload stage
- **HCP projects, variable sets, health assessments** — add when stamping a second client
- **`terraform test` suite** — post-multi-client
- **RDS Proxy, NAT-optional mode** — optional platform features
- **App code change to read all DB conn info from secret** (instead of userdata env vars) — noted in `shared/outputs.tf`; would enable trimming `rds_endpoint`/`db_name`/`db_app_username` outputs further

## Structure

```
terraform/
├── shared/                       ← ha-3tier-shared-prod
│   ├── cloud.tf
│   ├── main.tf                   # VPC, security, RDS, secrets, endpoints, endpoint policy,
│   │                             # KMS, SSM doc, ACM, Route53, modernised log bucket
│   ├── db_bootstrap.tf           # Lambda + RESOURCE invocation (v2)
│   ├── variables.tf              # port-contract vars
│   ├── outputs.tf                # TRIMMED in v3
│   ├── terraform.tfvars
│   └── lambda/db-bootstrap/
│       ├── lambda_function.py
│       └── .gitignore
├── compute/                      ← ha-3tier-compute-prod
│   ├── cloud.tf
│   ├── main.tf                   # ALBs, ASGs, full WAF (v2), Route53 alias
│   ├── variables.tf              # waf_rate_limit
│   ├── outputs.tf
│   ├── terraform.tfvars
│   └── run_trigger.tf.example    # NEW in v3 (optional, codified run trigger)
├── modules/
│   ├── rds/                      # prevent_destroy, retention 14
│   ├── alb/                      # accepts access_log_bucket_id
│   ├── ec2-asg/                  # latest_version, scoped IAM
│   ├── security/                 # full module (v2) — port chain explicit
│   └── vpc/INTERFACE.md
└── legacy/

scripts/
├── app_userdata.sh
└── web_userdata.sh

.github/workflows/
├── terraform-plan-shared.yml
├── terraform-apply-shared.yml
├── terraform-plan.yml
├── terraform-apply.yml
└── deploy-app.yml
```

## Required GitHub setup

Before first shared apply:

1. Repo → Settings → Environments → New → `shared-prod`
2. Add yourself as required reviewer
3. Restrict to `main` branch

This forces a human approval click before any RDS/VPC/DNS change lands.

## Shared → compute run trigger (REFACTOR.md Step 4)

After first shared apply, either:
- **UI click** (recommended, 30 sec): HCP → compute workspace → Settings → Run Triggers → add shared as source, OR
- **Codify**: rename `run_trigger.tf.example` → `run_trigger.tf` (needs TFE_TOKEN, see file header)
