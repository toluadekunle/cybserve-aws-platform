# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

Infrastructure-as-code for a HA 3-tier web app deployed to AWS `eu-west-2` via HCP Terraform. No application source lives here — only the platform (network, RDS, ASGs, ALBs, WAF, DNS) and the GitHub Actions that drive it. Long-form design history is in `README.md` (v3 change log) and `REFACTOR.md` (step-by-step migration playbook).

## Commands

All Terraform commands are run from the **repo root** using `-chdir` — do not `cd` into `terraform/shared` or `terraform/compute`. This was a deliberate fix (see commit `89aa592`); running `terraform` from inside those dirs breaks relative module/script paths.

```bash
# Shared workspace (VPC, RDS, secrets, DNS, Lambda bootstrap)
terraform -chdir=terraform/shared init
terraform -chdir=terraform/shared fmt -check -recursive .
terraform -chdir=terraform/shared validate
terraform -chdir=terraform/shared plan
terraform -chdir=terraform/shared apply

# Compute workspace (ALBs, ASGs, WAF, Route53 alias)
terraform -chdir=terraform/compute init
terraform -chdir=terraform/compute plan
terraform -chdir=terraform/compute apply
```

There is no test suite, linter, or build step beyond `terraform fmt` / `validate`. The Lambda package (`terraform/shared/lambda/db-bootstrap/`) is built at apply time by a `null_resource` + `local-exec` that runs `pip3 install pymysql` into `build/` and zips it. Don't commit `build/` or `build.zip` — they're gitignored.

## Architecture — two-workspace split

The stack is split across two HCP workspaces with a strict, one-way dependency:

```
ha-3tier-shared-prod   (terraform/shared/)   — long-lived, RDS lives here
        │
        │   tfe_outputs.nonsensitive_values
        ▼
ha-3tier-compute-prod  (terraform/compute/)  — ephemeral, can be destroyed/rebuilt freely
```

Compute reads shared state via `data "tfe_outputs" "shared"` in `terraform/compute/main.tf`. This is preferred over `terraform_remote_state` in HCP. **Every output that crosses this boundary must be non-sensitive** so it surfaces in `nonsensitive_values`. `terraform/shared/outputs.tf` is deliberately trimmed — only what compute actually consumes plus a small "operator visibility" set (e.g. `route53_name_servers`). When adding a cross-workspace value, add it there and mirror the local alias in `compute/main.tf`.

A **run trigger** on the compute workspace re-plans compute after a successful shared apply. This is configured via the HCP UI (Compute workspace → Settings → Run Triggers → source = shared). An optional codified alternative lives at `terraform/compute/run_trigger.tf.example` (rename to `.tf` if desired, requires `TFE_TOKEN`).

## GitHub Actions

Four workflows, all driven by `paths:` filters against the two workspace dirs plus `terraform/modules/**`:

| Workflow | Trigger | Purpose |
|---|---|---|
| `terraform-plan-shared.yml` | PR to main touching `terraform/shared/**` or shared modules | Plan shared, comment on PR |
| `terraform-apply-shared.yml` | Push to main, same paths | Apply shared — **gated on `shared-prod` GitHub environment** (required reviewer) |
| `terraform-plan.yml` | PR to main touching `terraform/compute/**`, `terraform/modules/**`, `scripts/**` | Plan compute, comment on PR |
| `terraform-apply.yml` | Push to main, same paths | Apply compute — no environment gate (blast radius is low) |
| `deploy-app.yml` | Push to main touching `app/**` or `packer/**` | Packer build → commit new AMI ID to `terraform/compute/terraform.tfvars` with `[skip ci]` → apply compute |

When adding a resource to shared, also add its module path to the `terraform-plan-shared.yml` / `terraform-apply-shared.yml` `paths:` list if it lives under `terraform/modules/` — only `vpc`, `security`, and `rds` are currently wired to the shared workflows.

The `shared-prod` environment must be configured manually in GitHub (Settings → Environments) with a required reviewer before the first shared apply will unblock. This is a one-time setup.

## Critical design decisions (non-obvious)

Things that look editable but will break things if you change them without understanding why:

- **`random_password` + two secrets**. The RDS master credential exists only to bootstrap; the Lambda then creates `app_user` with least privilege and writes its credentials to a second secret. The app tier's IAM is scoped only to the app secret — never the master. Don't consolidate these.
- **`aws_lambda_invocation` as a *resource*, not data source** (`terraform/shared/db_bootstrap.tf`). Data sources evaluate on every plan/refresh, which would re-invoke bootstrap on every PR. The resource form with `lifecycle_scope = "CREATE_ONLY"` and explicit `triggers` is correct. All SQL in `lambda_function.py` must stay idempotent because triggers (secret rotation, code hash change) cause re-invocation.
- **RDS has `prevent_destroy = true` + `deletion_protection = true`** (`terraform/modules/rds/`). `terraform destroy` on shared will fail — this is by design. If you genuinely need to destroy (e.g. restoring from snapshot), both must be removed in a prior apply.
- **Route53 zone lives in shared, A-alias lives in compute**. This is what makes `terraform destroy` on compute safe: tearing compute down leaves the zone and NS delegation intact, so `terraform apply` rebuilds the alias with no GoDaddy involvement. Don't move the alias into shared.
- **ALB access-log bucket lives in shared**, consumed by the ALB module via `access_log_bucket_id`. Logs survive compute rebuilds. Bucket policy has both the modern `logdelivery.elasticloadbalancing.amazonaws.com` principal and the legacy `aws_elb_service_account` principal — `eu-west-2` currently needs the legacy fallback; keep both.
- **`SSM-SessionManagerRunShell` is account-wide**. It's AWS's reserved document name — only one per account-region. This stack sets it. If you fork for a second workload in the same account, extract SSM/KMS/audit into an account-baseline stack before both stacks fight over the document (noted in README "Multi-client notes" and REFACTOR.md appendix).
- **`latest_version` on ec2-asg launch templates** is load-bearing — removing it resurrects the "Error 15" instance-refresh loop.
- **Secrets Manager VPC endpoint policy is scoped to the two secrets** (`terraform/shared/main.tf`). Don't broaden it — this is the exfil-blast-radius control for a compromised instance role.

## When editing modules

- `modules/vpc/` is treated as pre-existing and the repo only documents its interface in `modules/vpc/INTERFACE.md`. If you change VPC, keep that contract (`vpc_id`, `public_subnet_ids`, `private_app_subnet_ids`, `private_data_subnet_ids`) intact or every consumer breaks.
- `modules/security/` defines the tier-to-tier port chain (ALB → web → internal ALB → app → RDS) via explicit `alb_listen_ports`, `web_listen_port`, `app_listen_port`, `db_port` inputs passed from shared. Change ports in `shared/variables.tf`, not inside the module.
- `modules/ec2-asg/` gates IAM for Secrets Manager behind `needs_secrets_access` — the web tier passes `false` (no DB creds), app tier passes `true` with `secret_arn = local.db_app_secret_arn`.

## Migration-from-running-state (rare)

The stack this repo manages was built from empty — no import was needed. If you ever replicate this refactor against a live workspace, follow the `state rm` → `import` order in `REFACTOR.md` Appendix A verbatim. The failure mode to avoid is dual ownership: two workspaces both claiming the same AWS object.

## Known scope gaps (intentional)

Deferred work is listed at the top of `README.md` ("Deliberate scope decisions"). Notable for planning: GitHub Actions still uses static AWS keys (target: OIDC); no `terraform test` suite yet; no RDS Proxy. Don't add these speculatively — they're scheduled for the multi-client stage.


## Hard rules (operator constraints)

- AWS profile is `ha3` (account 226031876177, region eu-west-2). Never assume a different profile.
- HCP Terraform org is Cybserve. All state lives there, never local.
- Never run `terraform apply` without first showing `terraform plan` output and waiting for explicit approval in chat. Plan-then-pause-then-apply.
- Never commit secrets, AWS keys, .tfvars with values, or anything matching the pattern AKIA[A-Z0-9]{16}.
- Treat any pre-existing AWS access key found in the repo as exposed and flag it — do not edit, do not delete, just flag.
- Branch `test/first-shared-plan` is the active workspace-split refactor. Preserve the two-workspace pattern. If a change would collapse it back to a single workspace, stop and ask.
- Cost matters. Before suggesting any change that creates resources, state the rough monthly cost.
