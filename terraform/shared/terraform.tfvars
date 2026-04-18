project_name = "ha-3tier"
environment  = "prod"
aws_region   = "eu-west-2"

# Networking
vpc_cidr                  = "10.0.0.0/16"
availability_zones        = ["eu-west-2a", "eu-west-2b"]
public_subnet_cidrs       = ["10.0.1.0/24", "10.0.2.0/24"]
private_app_subnet_cidrs  = ["10.0.11.0/24", "10.0.12.0/24"]
private_data_subnet_cidrs = ["10.0.21.0/24", "10.0.22.0/24"]

# Database
db_name                     = "appdb"
db_master_username          = "dbadmin"
db_app_username             = "app_user"
db_instance_class           = "db.t3.micro"
db_allocated_storage        = 20
db_backup_retention_period  = 14

# DNS
enable_route53    = true
route53_zone_name = "app.cybserve.co.uk"

# Operational
alb_log_retention_days = 90
