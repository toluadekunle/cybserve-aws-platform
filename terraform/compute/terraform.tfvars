project_name = "ha-3tier"
environment  = "prod"
aws_region   = "eu-west-2"

shared_workspace_name = "ha-3tier-shared-prod"
shared_organization   = "Cybserve"

# Packer-built AMIs — replaced automatically by deploy-app.yml on app.py change.
# These MUST be valid AMI IDs in eu-west-2 or plan will fail.
web_ami_id = "ami-0fa4a29703d31133d"
app_ami_id = "ami-0b91584c589a6b47c"

web_instance_type = "t3.small"
app_instance_type = "t3.small"

web_asg_min_size         = 2
web_asg_max_size         = 4
web_asg_desired_capacity = 2

app_asg_min_size         = 2
app_asg_max_size         = 4
app_asg_desired_capacity = 2

enable_waf = true
