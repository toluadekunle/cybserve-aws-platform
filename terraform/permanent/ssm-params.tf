########################################
# SSM Parameter Store — AMI ID pointers
#
# Packer writes the AMI ID here after a successful build.
# Terraform (burst layer) reads from here at plan time.
# This replaces the old pattern of `deploy-app.yml` doing
# sed + git push to terraform.tfvars.
#
# Type: String (not SecureString — AMI IDs are not secrets,
# they're identifiers visible to anyone with EC2 read).
#
# `lifecycle { ignore_changes = [value] }` means Terraform
# creates the parameter once with a placeholder, and Packer
# owns updates thereafter. Terraform will NOT drift-correct
# the value.
########################################

locals {
  ami_parameters = {
    "prod-web"    = "/${var.project_name}/prod/web-ami-id"
    "prod-app"    = "/${var.project_name}/prod/app-ami-id"
    "staging-web" = "/${var.project_name}/staging/web-ami-id"
    "staging-app" = "/${var.project_name}/staging/app-ami-id"
  }
}

resource "aws_ssm_parameter" "ami" {
  for_each = local.ami_parameters

  name        = each.value
  description = "AMI ID written by Packer — read by burst-layer Terraform"
  type        = "String"
  tier        = "Standard"
  value       = "placeholder-awaiting-first-packer-build"

  lifecycle {
    ignore_changes = [value]
  }

  tags = {
    Name  = each.key
    Owner = "packer"
  }
}
