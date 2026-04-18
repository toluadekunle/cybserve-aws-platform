# Client-ready refactor v3 — migration playbook

Two-workspace split for `ha-3tier-webapp`.

---

## Pre-flight

1. **Stack destroyed?**
   ```bash
   aws --profile ha3 --region eu-west-2 ec2 describe-instances \
     --filters "Name=tag:Project,Values=ha-3tier" \
     --query 'Reservations[].Instances[].InstanceId'
   ```
   Expect `[]`.

2. **Back up old workspace state** — HCP → `ha-3tier-webapp-prod` → States → download latest.

3. **Create two new HCP workspaces:**
   - `ha-3tier-shared-prod`
   - `ha-3tier-compute-prod`

   Both need the same env vars as the old workspace (`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`).

4. **Rotate** `AKIATJIEMXBIT7L2BPMT` before anything else.

5. **GitHub environment for shared apply gate:**
   - Repo → Settings → Environments → New → `shared-prod`
   - Add yourself as a required reviewer
   - Restrict to `main` branch

---

## Step 1 — Pull the refactor into your repo

```bash
REPO=~/src/ha-3tier-webapp
REFACTOR=~/ha-3tier-refactor-v3

git -C $REPO checkout -b feature/client-ready-refactor-v3

# New workspace directories
cp -r $REFACTOR/terraform/shared  $REPO/terraform/shared
cp -r $REFACTOR/terraform/compute $REPO/terraform/compute

# Modified modules
cp $REFACTOR/terraform/modules/rds/*.tf      $REPO/terraform/modules/rds/
cp $REFACTOR/terraform/modules/alb/*.tf      $REPO/terraform/modules/alb/
cp $REFACTOR/terraform/modules/ec2-asg/*.tf  $REPO/terraform/modules/ec2-asg/

# Full reference security module (replaces your existing one).
# Back up yours first, diff before deleting the backup.
mv $REPO/terraform/modules/security $REPO/terraform/modules/security.backup
cp -r $REFACTOR/terraform/modules/security   $REPO/terraform/modules/

# VPC module: kept — interface doc only.
cp $REFACTOR/terraform/modules/vpc/INTERFACE.md $REPO/terraform/modules/vpc/INTERFACE.md

# Userdata
cp $REFACTOR/scripts/*.sh $REPO/scripts/

# Workflows (5 total: 2 new shared, 3 existing retargeted to compute/)
cp $REFACTOR/.github/workflows/*.yml $REPO/.github/workflows/

# Archive old root tf files
mkdir -p $REPO/terraform/legacy
for f in cloud.tf main.tf variables.tf outputs.tf terraform.tfvars terraform.tfvars.example; do
  [ -f $REPO/terraform/$f ] && git -C $REPO mv terraform/$f terraform/legacy/$f
done
cp $REFACTOR/terraform/legacy/README.md $REPO/terraform/legacy/README.md
```

Diff the security modules before deleting the backup:
```bash
diff -u $REPO/terraform/modules/security.backup/main.tf \
        $REPO/terraform/modules/security/main.tf
```
When satisfied: `rm -rf $REPO/terraform/modules/security.backup`

---

## Step 2 — Apply shared

```bash
cd $REPO/terraform/shared
terraform init
terraform plan
```

Expect ~30 resources:
- VPC + subnets + 2 NAT + IGW
- 5 security groups (alb, int_alb, web, app, rds)
- RDS Multi-AZ with `prevent_destroy = true` + `deletion_protection = true` (takes ~10 min)
- 2 secrets (db-master, db-app)
- 5 VPC interface endpoints + Secrets Manager endpoint policy
- KMS key + alias for SSM logs
- SSM doc + KMS-encrypted CloudWatch log group
- ACM cert + validation records + validation resource
- Route53 zone (new NS records)
- ALB log bucket + ownership controls + modernised policy
- Lambda + SG + IAM + invocation (resource, not data source — v2 fix)

Apply:
```bash
terraform apply
```

Capture the NS records:
```bash
terraform output route53_name_servers
```

---

## Step 3 — Delegate the subdomain in GoDaddy (one-time only)

In GoDaddy DNS for `cybserve.co.uk`:
- Add four NS records, host `app`, pointing at the four nameservers above.
- Wait 5–10 minutes.

Confirm ACM issued:
```bash
aws --profile ha3 --region eu-west-2 acm list-certificates \
  --query 'CertificateSummaryList[?DomainName==`app.cybserve.co.uk`].[Status]'
```
Expect `[ "ISSUED" ]`.

**Last time you touch GoDaddy.**

---

## Step 4 — Set up the run trigger (one-time, 30 seconds)

This makes compute auto-plan whenever shared applies successfully.
Without it, shared changes land and compute sits stale until you remember.

**Option A — UI click (recommended):**
1. HCP Terraform → `ha-3tier-compute-prod` → Settings → Run Triggers
2. Source Workspace → select `ha-3tier-shared-prod`
3. Click "Add Run Trigger"

**Option B — Codified:**
Rename `terraform/compute/run_trigger.tf.example` → `run_trigger.tf`. Requires a `TFE_TOKEN` env var in the compute workspace with "Manage Workspaces" permission on compute-prod. See the file header for full prerequisites.

Use Option A unless you have a reason to codify it. The UI click is a 30-second setup, takes no provider auth, and is what HashiCorp's own docs recommend for this scenario.

---

## Step 5 — Apply compute

```bash
cd ../compute
terraform init
terraform plan
```

Expect:
- External + internal ALBs (consuming the shared log bucket)
- Web + app ASGs (no SSH, IMDSv2, SSM-only access)
- WAFv2: Common + KnownBadInputs + IpReputationList + RateLimit (2000/5min per IP) + CloudWatch logging with redacted auth/cookie headers
- Route53 A-alias → external ALB

Apply, verify:
```bash
terraform apply
curl -I http://app.cybserve.co.uk        # 301 → HTTPS
curl -I https://app.cybserve.co.uk       # 200
curl https://app.cybserve.co.uk/api/stats
```

---

## Step 6 — Rebuild drill (the proof)

```bash
cd $REPO/terraform/compute
terraform destroy     # RDS persists. ALBs, WAF, ASGs, alias gone.
# ~2 min
terraform apply       # Everything back. DB records intact.
curl https://app.cybserve.co.uk/api/stats   # same record count as before
```

Zero GoDaddy steps. Zero manual DNS. That's client-ready.

---

## Step 7 — Retire the old workspace

Once the rebuild drill passes clean:

1. HCP → `ha-3tier-webapp-prod` → Settings → Destroy
   - Queue a destroy plan. It should show **nothing to destroy** (all resources migrated).
   - If it shows resources — STOP. Don't confirm. Run the migration appendix below.

2. Delete the workspace.

3. Merge the PR. Delete `terraform/legacy/` in a follow-up PR after a month.

---

## Rollback

```bash
cd terraform/shared
terraform destroy   # RDS prevent_destroy will BLOCK.
                    # Correct. Only disable if genuinely restoring from snapshot.
```

To revert to single-workspace:
```bash
git checkout main
cd terraform
mv legacy/*.tf .
mv legacy/terraform.tfvars .
# Re-apply the old workspace from HCP UI
```

---

## Multi-client notes (future, not now)

Two v3 components are scoped to a single-workload account:

1. **`SSM-SessionManagerRunShell` document** — AWS's reserved default. Only one per account-region. Multi-workload = collision.
2. **GitHub Actions static AWS keys** — per-workflow OIDC roles are cleaner.

When a second client arrives: extract SSM + KMS + audit logging into an account-baseline stack, migrate GitHub Actions → AWS via OIDC.

---

## Cost

- Shared running: ~$9–10/day (NAT x2, RDS Multi-AZ, VPCE x5)
- Compute running: ~$1–2/day (ALBs + EC2 + WAF)
- Compute destroyed: compute $0; shared persists
- Route53 zone: $0.50/month
- Lambda: pennies
- KMS key: $1/month + $0.03 per 10,000 requests

---

## Appendix A — Migrating from a running workspace

This appendix is for the case where the old `ha-3tier-webapp-prod` workspace is managing live resources and you can't destroy first. Your current stack is destroyed, so you don't need this now. But if you ever replicate this refactor for another environment where the old state is live:

### The rule

Never let two workspaces own the same real AWS object. Either state has to let go first, then the other state imports.

### The order

1. **Back up old state** — HCP → States → download. Keep the JSON locally.
2. **Write the new shared and compute configs** (this refactor provides them).
3. **Lock the old workspace** — HCP → Settings → lock. Prevents accidental runs during migration.
4. **Detach shared-owned resources from old state, don't destroy:**
   ```bash
   cd path/to/old/workspace
   terraform state rm module.vpc
   terraform state rm module.security
   terraform state rm module.rds
   terraform state rm aws_secretsmanager_secret.db_password
   terraform state rm aws_secretsmanager_secret_version.db_password
   terraform state rm aws_acm_certificate.main
   # ...and any other shared-layer resources
   ```
   These resources now exist in AWS but no Terraform state manages them. Do NOT `terraform apply` in the old workspace now — it would try to recreate them.
5. **Import into the new shared workspace:**
   ```bash
   cd terraform/shared
   terraform init
   terraform import 'module.vpc.aws_vpc.main' vpc-0abc...
   terraform import 'module.rds.aws_db_instance.main' ha-3tier-prod-db
   # ...etc
   ```
   Use `import` blocks in HCL (Terraform 1.5+) where practical — they're reviewable in plan.
6. **Plan** the new shared. Expect "No changes" for everything imported. If there are diffs, your config doesn't match reality — investigate, don't apply.
7. **Apply** new shared. Should be a no-op if step 6 was clean.
8. **Repeat for compute:** `state rm` the ALB/ASG/WAF resources from old, `import` into new compute.
9. **Plan compute.** Again expect "No changes."
10. **Apply compute.**
11. **Unlock the old workspace. Queue a destroy plan.** If anything shows up, you missed something — go back to step 4 for that resource.
12. **Delete the old workspace.**

### Why this order

- `state rm` first means the old workspace forgets the resource without touching AWS.
- Then import means the new workspace picks up the AWS resource without creating a second one.
- The period between detach and import is the only window where the resource is unmanaged — keep it short.

### The failure mode to avoid

If you import into the new workspace **before** `state rm` from the old one, both workspaces now think they own the same AWS resource. Whichever runs first on its next apply could destroy the resource, or they could fight each other on tags, attributes, or drift. This is the "dual ownership" bug. Always detach first.

### HashiCorp's own guidance

HashiCorp's state docs confirm:
- `terraform state rm` removes an object from state without destroying it.
- `terraform import` brings an existing object under state management.
- Using them in this order is the supported way to move resources between configurations.
