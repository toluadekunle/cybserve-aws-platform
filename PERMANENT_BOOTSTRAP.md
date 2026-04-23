# Permanent-layer bootstrap — one-time setup

This document lists everything a human has to do outside of `terraform apply` to bring the permanent layer online. You do this once, in the order given. After it's done, the permanent layer is self-managing via HCP + OIDC — you never repeat these steps.

Estimated elapsed time: **~90 minutes active work**. (Optional domain transfer is a 7-day background task and is not required.)

---

## Stage 0 — Account hygiene (do first, blocks everything else)

### 0.1 Root account

1. Enable **hardware MFA** on the AWS account root. YubiKey or equivalent. Note: virtual MFA is not acceptable at this bar.
2. Store the root password + MFA recovery code in a sealed envelope in a safe. Not a password manager. Not 1Password. Physical paper, physical safe. This is break-glass material, used twice a decade.
3. Delete any access keys on the root account. `aws iam list-access-keys` on the root identity should return empty.

### 0.2 Account alternate contacts

Console → My Account → Alternate Contacts. Set the Security and Operations contacts to a monitored address (ideally a shared alias, not your personal email). AWS uses these for notifications that don't hit CloudTrail.

### 0.3 Region lockdown

Console → Account → IAM → Account settings → STS. Deactivate every region you don't operate in. Leave `eu-west-2` active. This shrinks the blast radius of any credential compromise.

### 0.4 Service Quota for IAM

Check that IAM OIDC providers quota is at least 2 (default is 100, should be fine). Nothing to do here unless you've hit limits before.

---

## Stage 1 — DNS delegation at Cloudflare

**Target state:** registrar at Cloudflare, DNS at Cloudflare, subdomain hosted zones at Route 53 (Terraform-managed). This decouples domain identity (Cloudflare) from workload hosting (AWS), which is a specific point a production-grade security reviewer looks for.

Two independent migrations:

**1a. DNS migration (do this before Stage 4's first apply — 30 min active work, hours to propagate)**

1. Sign up at Cloudflare if you don't have an account. Enable hardware-key or TOTP 2FA **immediately** on the account. Store recovery codes in the same physical safe as AWS root recovery codes.
2. Cloudflare dashboard → Add a Site → `cybserve.io` → Free plan.
3. Review Cloudflare's DNS import. Delete any GoDaddy parking records. Leave apex empty unless you have active apex use (email MX, www redirect).
4. Cloudflare gives you two nameservers (e.g. `chad.ns.cloudflare.com`, `fay.ns.cloudflare.com`). Note them.
5. GoDaddy → `cybserve.io` → DNS → Nameservers → "Enter my own nameservers" → paste the Cloudflare pair. Save.
6. Verify: `dig NS cybserve.io +short` should return the Cloudflare nameservers. 5–30 min typical.

**1b. NS delegation after Stage 4 (5 min at Cloudflare)**

After the first apply emits `route53_prod_name_servers` and `route53_staging_name_servers`:

1. Cloudflare dashboard → `cybserve.io` → DNS → Records.
2. Add 4 NS records for host `app`, each pointing at one of the prod zone nameservers.
3. Add 4 NS records for host `app-staging`, each pointing at one of the staging zone nameservers.
4. Verify: `dig NS app.cybserve.io +short` should return the Route 53 prod nameservers.

**That is the only touch of the Cloudflare DNS panel, ever.** Destroying and rebuilding burst layers does not rotate permanent-layer zone NS records.

**1c. Registrar transfer (non-blocking, 5–7 days, do anytime)**

The transfer can run in parallel with Phase 1 apply — DNS stays at Cloudflare throughout.

1. GoDaddy: unlock `cybserve.io`, disable WHOIS privacy, request authorization code. Verify registrant email is current.
2. Cloudflare → Domain Registration → Transfer Domains → enter `cybserve.io` + auth code. Pay one year's renewal (~£11 for `.io` at-cost).
3. Approve the GoDaddy confirmation email promptly (skips the 5-day ICANN auto-approve).
4. Cloudflare emails when complete.
5. Post-transfer: verify auto-renew, WHOIS privacy, and transfer lock are ON (all default). Remove payment method at GoDaddy.

### Follow-up — optionally codify NS delegation via the `cloudflare` Terraform provider

If you want the 8 NS delegation records managed by Terraform instead of clicked in, we can add a small Cloudflare-provider block to `dns.tf` later. Requires a Cloudflare API token scoped to Zone:DNS:Edit for `cybserve.io`. Deferred — it's a small quality-of-life improvement, not a security control.

---

## Stage 2 — HCP organization + workspace setup

Five workspaces across three projects. Every setting matters — mistakes here cause the hardest-to-debug problems later (wrong working directory swallows `.tfvars` silently; wrong env-var type leaks secrets into plan output; auto-apply-on means a rushed merge becomes a prod apply).

Do not skip the "Do NOT" callouts at the end of this stage.

### 2.1 Confirm org ownership

Sign in at https://app.terraform.io. Top-left account switcher → select `Cybserve`. Top-right avatar → Organization Settings → you should see yourself listed with role `Owner`. If not, fix before continuing.

### 2.2 Create the three projects

Left sidebar → "Projects and workspaces" (default view).

For each of the three projects below:

1. Click the **"New"** button (top-right) → **"Project"**
2. Name: (from table)
3. Description: (from table — matters for future operators scanning the list)
4. Click **"Create"**

| Name | Description |
|---|---|
| `ha-3tier-prod` | Production environment — burst + permanent workspaces |
| `ha-3tier-staging` | Staging environment — burst workspaces |
| `ha-3tier-meta` | Governance — codified HCP + GitHub config (Phase 2+) |

**Verify:** the left sidebar project dropdown now shows all three.

### 2.3 Create the five workspaces

All five follow the same creation flow. Steps below are for the first one; repeat the pattern 4 more times.

#### 2.3.a — Create `ha-3tier-permanent-prod`

1. Top-right **"New"** → **"Workspace"**

2. **Choose a workflow:** click **"CLI-driven workflow"**
   - ⚠️ NOT "Version control workflow" — we switch to VCS only in Stage 6, after OIDC is wired up. Starting VCS-driven creates a chicken-and-egg we'd have to unwind.

3. **Configure settings:**
   - **Project**: `ha-3tier-prod` (dropdown)
   - **Workspace Name**: `ha-3tier-permanent-prod`
   - **Description**: `Permanent layer — OIDC, IAM, KMS, audit stack, Private CA, Route53 zones. Never destroyed.`

4. Click **"Create workspace"**

5. You land on the workspace's overview page. **Do not queue a plan.** The workspace has no config loaded yet.

#### 2.3.b — Configure workspace settings (critical)

On the new workspace page, navigate:

- Top nav **Settings** → **General**

Set each field to **exactly** this (defaults are usually right, but verify):

| Field | Value | Why |
|---|---|---|
| **Execution Mode** | `Remote` | HCP runs Terraform on their runners. State lives in HCP. This is what "Remote" means in HCP Terraform — unrelated to CLI-driven vs VCS-driven. |
| **Apply Method** | `Manual apply` (not "Auto apply") | Every apply requires a human click. Non-negotiable for our defensibility bar. |
| **Terraform Working Directory** | **LEAVE BLANK** | This field only applies to VCS-driven runs. We're CLI-driven — the working directory comes from the `-chdir` flag on the command line. Setting it here now causes confusing behaviour during Stage 4. We'll set it to `terraform/permanent` in Stage 6 when we switch to VCS. |
| **Terraform Version** | **Pin to a specific version**, e.g. `1.9.8` | NOT "latest". Latest moves; plans that worked last week fail after a silent upgrade. Pinned version = reproducible applies. The repo's `required_version` allows `>= 1.6.0`, so any recent version works — pick the current stable and write it down. |
| **User Interface** | `Structured Run Output` (default) | Better visual diff reading |

Click **"Save settings"**.

Do **not** touch these other tabs yet:
- **Variables** — Stage 4 and 5 manage these with exact values
- **Version Control** — Stage 6 connects this
- **Notifications** — later, optional
- **Run Triggers** — Phase 2 uses this for shared → compute
- **Team Access** — RBAC is Phase 5+, defaults fine for sole operator

#### 2.3.c — Repeat for the four burst workspaces

Same flow as 2.3.a + 2.3.b, four times:

| Workspace Name | Project | Description |
|---|---|---|
| `ha-3tier-shared-prod` | `ha-3tier-prod` | Prod burst: VPC, Aurora, secrets, internal ACM |
| `ha-3tier-compute-prod` | `ha-3tier-prod` | Prod burst: ALBs, ASGs, WAF, route53 alias |
| `ha-3tier-shared-staging` | `ha-3tier-staging` | Staging burst: VPC, Aurora, secrets |
| `ha-3tier-compute-staging` | `ha-3tier-staging` | Staging burst: ALBs, ASGs, WAF |

Every one of them: **CLI-driven workflow, Remote execution, Manual apply, Working Directory blank, Terraform version pinned to the same value as permanent, no variables.**

These stay empty (no config, no runs) until Phase 2 drops Terraform files into `terraform/shared` and `terraform/compute`.

### 2.4 Verification

Go to `https://app.terraform.io/app/Cybserve/workspaces`. The filter UI should show:

- 5 workspaces total
- 3 in project `ha-3tier-prod` (permanent, shared-prod, compute-prod)
- 2 in project `ha-3tier-staging` (shared-staging, compute-staging)
- 0 in project `ha-3tier-meta` (correct — it's for Phase 2)
- Every workspace shows "No runs" or similar
- Every workspace shows "CLI-Driven Workflow" as the trigger type
- Every workspace shows the same pinned Terraform version

If any of these don't match, fix now — much cheaper than debugging after Stage 4.

### 2.5 Do NOT do any of these yet (common mistakes)

Past problems from real setups:

- ❌ **Do NOT add any Workspace Variables** (neither "Terraform variables" nor "Environment variables"). Stage 4 adds temporary AWS creds as Environment variables with specific names + sensitivity flags; Stage 5 replaces them with OIDC config. Adding them now either duplicates work or contradicts it.
- ❌ **Do NOT connect the workspace to GitHub.** Stage 6 does the permanent workspace; Phase 2 does the others. Connecting now triggers VCS behaviour that conflicts with CLI-driven.
- ❌ **Do NOT set a Terraform Working Directory.** CLI-driven doesn't need it; VCS-driven sets it in Stage 6. Setting it now causes HCP to look in a path that doesn't match your `-chdir` flag — you'll get "no Terraform configuration files" errors that are hard to diagnose.
- ❌ **Do NOT enable Auto Apply on any workspace, ever.** Our defensibility bar is "a human approves every apply." Auto Apply silently overrides that.
- ❌ **Do NOT queue a plan on any workspace yet.** Permanent has no config (we run it from CLI in Stage 4). The other 4 will remain empty until Phase 2.
- ❌ **Do NOT put AWS credentials as "Terraform variables".** They belong as "Environment variables" with **Sensitive** checked. Terraform variables render in plan output — a sensitive one leaks into logs.
- ❌ **Do NOT delete and recreate a workspace if you fumble a setting.** Every field is editable post-creation. Deleting wastes time and, for workspaces with state, is destructive.
- ❌ **Do NOT use the "latest" Terraform version.** Pin it. Changing the pin is a deliberate act; letting it drift is how Tuesday-morning runs start breaking for no reason.

---

## Stage 3 — Temporary bootstrap credentials (delete at end of Stage 5)

The permanent workspace creates the OIDC trust — which means the FIRST apply can't use OIDC. Chicken-and-egg. We solve this with a temporary IAM user that:
- Is used exactly once for the first apply
- Is deleted immediately after
- Never appears in Terraform state

### 3.1 Create the bootstrap user

AWS Console → IAM → Users → Create user.

- Name: `ha3-bootstrap-DELETEME`
- Access type: programmatic access (access key), console access disabled
- Attach policy: `AdministratorAccess` (temporary, deleted at the end of this stage)
- No permission boundary (we don't have one yet — it's what we're about to create)

Download the access key + secret immediately. Store in your local `~/.aws/credentials` under a profile called `ha3-bootstrap`.

### 3.2 Verify

```bash
aws --profile ha3-bootstrap sts get-caller-identity
```

Should return the `ha3-bootstrap-DELETEME` user ARN.

---

## Stage 4 — First apply of the permanent workspace

### 4.1 Check out the repo and this branch

```bash
cd ~/src/cybserve-aws-platform
git fetch origin
git checkout phase1/permanent-baseline
```

### 4.2 Configure the HCP workspace to use your local AWS credentials temporarily

HCP Console → `ha-3tier-permanent-prod` workspace → Variables → Add:

- Variable category: `Environment variable`
- Key: `AWS_ACCESS_KEY_ID`
- Value: from your `ha3-bootstrap` profile
- Sensitive: yes

- Variable category: `Environment variable`
- Key: `AWS_SECRET_ACCESS_KEY`
- Value: from your `ha3-bootstrap` profile
- Sensitive: yes

### 4.3 Run the first apply locally (not via HCP UI)

HCP's CLI-driven workflow lets you run Terraform from your laptop while state lives in HCP.

```bash
cd terraform/permanent
terraform login                           # if not already logged in to HCP
terraform -chdir=. init
terraform -chdir=. validate
terraform -chdir=. plan -out=permanent.tfplan
```

Review the plan. Expect ~80–100 resources:
- 7 KMS keys + aliases
- 4 S3 buckets + policies + lifecycle + encryption config
- CloudTrail + CloudWatch log group + IAM role + 14 metric filter alarms + SNS topic
- AWS Config recorder + delivery channel + ~26 managed rules + IAM role
- GuardDuty detector + 4 feature toggles
- 2 Access Analyzer analyzers
- Inspector v2 enabler
- Security Hub account + 3 standards subscriptions
- 2 OIDC providers
- IAM permission boundary policy
- HCP workspace roles (10 total: 5 workspaces × 2 phases)
- GitHub packer role + instance profile role
- Break-glass admin role + alarm
- ACM Private CA + self-signed root
- 2 Route53 zones + 2 public ACM certs + validation records
- 4 SSM AMI parameters

Apply:
```bash
terraform -chdir=. apply permanent.tfplan
```

First apply takes **~10 minutes** (Private CA self-signing + ACM validation are the slowest pieces).

### 4.4 Capture the outputs

```bash
terraform -chdir=. output
```

Note the following — you'll use them in Stage 5:
- `hcp_role_arns` — the role ARNs for each workspace phase
- `cis_alarms_sns_topic_arn` — you'll subscribe your email to this
- `route53_prod_name_servers` — you'll configure these at the parent registrar
- `breakglass_admin_role_arn` — this is your escape hatch

### 4.5 Set NS delegation at the `cybserve.io` registrar

At whichever registrar holds `cybserve.io`, add 4 NS records for host `app` pointing at `route53_prod_name_servers`, and 4 NS records for host `app-staging` pointing at `route53_staging_name_servers`. If the parent is already on Route 53, tell me and I'll switch this step to a Terraform block instead.

### 4.6 Subscribe to CIS alarms SNS topic

```bash
aws --profile ha3-bootstrap sns subscribe \
  --topic-arn <cis_alarms_sns_topic_arn-from-step-4.4> \
  --protocol email \
  --notification-endpoint tolu@cybserve.co.uk
```

Confirm the subscription from your email inbox.

---

## Stage 5 — Switch the permanent workspace to OIDC, delete bootstrap credentials

### 5.1 Configure HCP dynamic credentials for the permanent workspace

HCP Console → `ha-3tier-permanent-prod` → Variables → Add:

- `TFC_AWS_PROVIDER_AUTH` = `true`  (Environment variable)
- `TFC_AWS_RUN_ROLE_ARN` = `<the apply role ARN for ha-3tier-permanent-prod, from hcp_role_arns output>`

Then DELETE the two `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` variables from Stage 4.2.

### 5.2 Test OIDC path works

Queue a new plan from the HCP UI. It should succeed with zero changes (the permanent layer is already applied). Check the run log — it should show the role ARN being assumed via OIDC.

### 5.3 Configure OIDC for the other four workspaces

Repeat Stage 5.1 for `ha-3tier-shared-prod`, `ha-3tier-compute-prod`, `ha-3tier-shared-staging`, `ha-3tier-compute-staging`. Each gets its own apply-role ARN from the `hcp_role_arns` output.

These workspaces are still empty — they'll get their configs in Phase 2.

### 5.4 Delete the bootstrap user

```bash
aws --profile ha3-bootstrap iam delete-access-key --user-name ha3-bootstrap-DELETEME --access-key-id <your-bootstrap-key>
aws --profile ha3-bootstrap iam detach-user-policy --user-name ha3-bootstrap-DELETEME --policy-arn arn:aws:iam::aws:policy/AdministratorAccess
aws --profile ha3-bootstrap iam delete-user --user-name ha3-bootstrap-DELETEME
```

Remove the `ha3-bootstrap` profile from `~/.aws/credentials`.

Verify:
```bash
aws iam list-users
# Should return: Users: []
```

If anything shows up, you still have a long-lived credential in the account. This bar requires empty.

---

## Stage 6 — Switch permanent workspace to VCS-driven

### 6.1 Connect HCP to GitHub

HCP Console → Settings → Version Control → Add VCS provider → GitHub.
Authorize HCP's GitHub App to access `cybserve-aws-platform`.

### 6.2 Reconfigure the permanent workspace

`ha-3tier-permanent-prod` → Settings → Version Control → Connect to VCS.
- Repository: `toluadekunle/cybserve-aws-platform`
- Working directory: `terraform/permanent`
- Auto-apply: **off** (manual apply-click required, per our defensibility bar)
- Trigger patterns:
  - `terraform/permanent/**`
  - `.github/workflows/terraform-plan-permanent.yml`

### 6.3 Branch protection on main

GitHub → Settings → Branches → Protect main:
- Require pull request before merging (with 1 approval)
- Require status checks: `Plan (permanent)`, `Plan (shared)`, `Plan (compute)` (these will exist after Phase 2)
- Require conversation resolution before merging
- Include administrators

This is clickops for now. Phase 2 will codify it via the `github` Terraform provider managed by the `ha-3tier-meta` workspace.

---

## Stage 7 — Verification

### 7.1 Defensibility checks

Run each of these and expect the stated result. If any fail, STOP — do not proceed to Phase 2.

```bash
# No IAM users exist
aws iam list-users --query 'length(Users)'              # expect: 0

# No access keys anywhere
aws iam list-users --query 'Users[].UserName' | \
  xargs -I{} aws iam list-access-keys --user-name {}    # expect: empty

# CloudTrail is active and encrypted
aws cloudtrail describe-trails --query 'trailList[0].[IsLogging,KmsKeyId]'
aws cloudtrail get-trail-status --name ha-3tier-trail \
  --query '[IsLogging,LatestDeliveryTime]'

# CloudTrail bucket has object lock
aws s3api get-object-lock-configuration \
  --bucket $(aws s3api list-buckets --query 'Buckets[?starts_with(Name,`ha-3tier-cloudtrail`)].Name' --output text)
# Expect: ObjectLockConfiguration with Mode=COMPLIANCE

# Security Hub standards are all ENABLED
aws securityhub get-enabled-standards \
  --query 'StandardsSubscriptions[].StandardsStatus'    # expect: all "READY"

# GuardDuty detector active
aws guardduty list-detectors --query 'DetectorIds[0]' | \
  xargs -I{} aws guardduty get-detector --detector-id {} \
  --query '[Status,DataSources.S3Logs.Status,DataSources.MalwareProtection.ScanEc2InstanceWithFindings.EbsVolumes.Status]'

# Access Analyzer active
aws accessanalyzer list-analyzers --query 'analyzers[].[name,status]'

# EBS default encryption on
aws ec2 get-ebs-encryption-by-default --query 'EbsEncryptionByDefault'  # expect: true
aws ec2 get-ebs-default-kms-key-id

# Inspector v2 enabled
aws inspector2 batch-get-account-status --account-ids $(aws sts get-caller-identity --query Account --output text) \
  --query 'accounts[0].resourceState'

# Config recorder running
aws configservice describe-configuration-recorder-status \
  --query 'ConfigurationRecordersStatus[0].recording'   # expect: true
```

### 7.2 Security Hub score

Console → Security Hub → Security Standards → CIS AWS Foundations Benchmark v1.4.0 and AWS Foundational Security Best Practices.

First pass in a fresh account usually lands at 70–85% because AWS defaults (default VPC SG, IAM password policy) differ from CIS expectations. Triage the findings before declaring Phase 1 done:
- `Default security group of every VPC should restrict all traffic` — fix by locking down default SGs (can be a small additional TF block)
- `IAM password policy` — only matters if you ever create IAM users (you don't); can suppress with documented reason
- `Root user` findings — you've addressed in Stage 0

Target after triage: ≥ 95%.

### 7.3 Cost check

AWS Console → Billing → Cost Explorer. After 24h, expect daily run rate to match the PERMANENT.md table (~£55/mo = ~£1.80/day).

If significantly higher, something is misconfigured — most likely GuardDuty S3 protection scanning lots of unexpected traffic. Investigate.

---

## What Phase 1 leaves you with

- Zero long-lived AWS credentials
- Every TF run uses OIDC; token TTL ≤ 1h
- CloudTrail writing to a bucket that literally cannot be deleted for 1 year, not even by root
- Security Hub + Config + GuardDuty + Inspector + Access Analyzer running, findings visible in the console right now
- Private CA ready for internal TLS
- Public certs for `app.cybserve.io` and `app-staging.cybserve.io` pre-validated and ready to attach
- AMI pointer slots in SSM, ready for Packer to fill
- Break-glass role with MFA enforcement

You can stop here and the account is already in a defensible state. Phase 2 adds the burst layer.

## Rolling back

If you ever need to undo Phase 1:

1. Detach permission boundary from all roles (so the boundary can be deleted)
2. Disable the audit services in this order: Inspector → Security Hub standards → Security Hub → GuardDuty features → GuardDuty → Access Analyzer → Config rules → Config recorder
3. `terraform destroy` on the permanent workspace

CloudTrail and its object-locked bucket will block the destroy. The object lock cannot be lifted within the retention period — this is by design. You have to wait out the retention (or copy the bucket contents elsewhere and file an AWS support case to delete the bucket early, which requires a signed affidavit from the account owner).

**This is a deliberate guardrail, not a bug.** If a rollback ever feels painful, it's working.
