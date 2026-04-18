# modules/vpc — interface contract

**Do not overwrite your existing `modules/vpc/` with anything from this
refactor.** The existing module works and this refactor doesn't change it.
This file just documents the interface that `terraform/shared/main.tf`
expects. If your module already exposes these, you're done.

## Required inputs

| Name | Type | Notes |
|---|---|---|
| `project_name` | string | |
| `environment` | string | |
| `vpc_cidr` | string | e.g. `10.0.0.0/16` |
| `availability_zones` | list(string) | len ≥ 2 |
| `public_subnet_cidrs` | list(string) | one per AZ |
| `private_app_subnet_cidrs` | list(string) | one per AZ |
| `private_data_subnet_cidrs` | list(string) | one per AZ |

## Required outputs

| Name | Type |
|---|---|
| `vpc_id` | string |
| `public_subnet_ids` | list(string) |
| `private_app_subnet_ids` | list(string) |
| `private_data_subnet_ids` | list(string) |

## Required resources (behavioural, not structural)

- VPC with the given CIDR
- 6 subnets (2 AZs × 3 tiers)
- Internet Gateway
- 2 NAT Gateways (one per AZ) in the public subnets
- Route tables: 1 public (0.0.0.0/0 → IGW), 2 private-app (0.0.0.0/0 → NAT in own AZ), 1 private-data (no default route — NAT traffic only via endpoints)
- VPC flow logs to CloudWatch

Verify with:

```bash
cd terraform/shared
terraform init
terraform validate
```

If validate fails on module.vpc inputs, your existing module needs one of
the vars above added. If it fails on outputs, add the missing output.
