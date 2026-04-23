# terraform/permanent — the always-on layer

This workspace manages the resources that persist between demo sessions. Everything in here is either free or cheap, and provides continuity of the security story: IAM trust, CMKs, CloudTrail, Config, Security Hub, GuardDuty, Access Analyzer, Inspector, Private CA, Route53 zone. None of it is torn down by `make down`.

## What lives here and why

| Concern | Resources | Why permanent |
|---|---|---|
| Identity | GitHub OIDC provider, HCP Terraform OIDC provider, workspace IAM roles, permission boundary, break-glass role | Can't be ephemeral — identity is the root of trust for everything else |
| Crypto | Customer-managed KMS keys for audit logs + cross-burst data (CloudTrail, Config, audit S3, Backup vault, Secrets Manager where cross-session, EBS default) | Rotations are slow, key deletion windows are minimum 7 days — fundamentally long-lived |
| Audit | CloudTrail (org-trail pattern adapted to single account), Config recorder, Security Hub (CIS + AFSBP), GuardDuty (all data sources), Access Analyzer, Inspector v2 | Evidence accrues. Destroying these breaks the "any day, any time" defensibility claim. Combined cost ~£10/mo |
| Trust stores | ACM Private CA in short-lived mode, public ACM cert for `app.cybserve.co.uk`, public ACM cert for `app-staging.cybserve.co.uk` | Private CA deletion takes 7–30 days minimum. Public cert validation is free to keep; re-validating wastes 5 min of every cold start. |
| DNS | Route53 hosted zone for `app.cybserve.co.uk` (+ staging) | Zone recreation rotates NS records → requires manual registrar update → kills the "rebuild from zero" claim |
| Artifacts | S3 buckets for CloudTrail, Config history, VPC flow-log archive, ALB access logs, AWS Backup vault | Survives destroy → rebuild, so evidence and backups persist |
| AMI pointers | SSM Parameter Store entries for `/ha-3tier/prod/web-ami-id` and `/ha-3tier/prod/app-ami-id` | Packer writes here, Terraform reads here. Decouples AMI bake cadence from platform apply cadence. |

## What does NOT live here (burst-layer, in `terraform/shared` and `terraform/compute` after Phase 2)

VPC, subnets, NAT, Aurora cluster, secrets, VPC endpoints, ALBs, ASGs, WAF, Route53 A-alias. All destroyed by `make down`.

## Idle cost

| Item | Monthly |
|---|---|
| CloudTrail (1 trail) | ~£1 |
| Config (recorder + managed rules) | ~£2 |
| GuardDuty | ~£3 |
| Security Hub | ~£1 |
| Inspector (when no instances running) | £0 |
| Access Analyzer | £0 |
| ACM Private CA short-lived mode | ~£40 |
| KMS CMKs (6 × £1) | ~£6 |
| Route53 hosted zone × 2 | ~£1 |
| S3 audit storage (small) | <£1 |
| **Total permanent idle** | **~£55/mo** |

## Defensibility guarantees this layer provides

- `aws iam list-users` returns empty → no human IAM users, no static keys
- `aws iam list-access-keys` across all users → empty
- CloudTrail is continuously recording, log-file-validation on, bucket object-lock in COMPLIANCE mode
- Security Hub CIS + AFSBP running, findings visible in the console at any moment
- GuardDuty running with ≥ 30-day finding memory — a reviewer sees continuity
- Access Analyzer running → zero external-access findings alarm if anything becomes publicly accessible
- Every CMK has rotation enabled; verified by a Config managed rule
- Every audit bucket is encrypted, versioned, public-access-blocked; verified by Config
- Private CA short-lived mode issues certs with 7-day lifetime, auto-renewed

## Bootstrap

See `PERMANENT_BOOTSTRAP.md` in repo root for the one-time out-of-band setup sequence (create HCP workspace, configure HCP → AWS dynamic credentials, first apply). After bootstrap, this workspace is fully self-managing via CI.
