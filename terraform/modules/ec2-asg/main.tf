########################################
# IAM role + instance profile
########################################
data "aws_iam_policy_document" "assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "instance" {
  name_prefix        = "${var.project_name}-${var.environment}-${var.tier}-"
  assume_role_policy = data.aws_iam_policy_document.assume.json

  tags = { Name = "${var.project_name}-${var.environment}-${var.tier}-role" }
}

resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.instance.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# Secrets Manager access scoped to the exact secret ARN —
# only attached for tiers that actually need DB creds.
resource "aws_iam_role_policy" "secrets" {
  count       = var.needs_secrets_access ? 1 : 0
  name_prefix = "${var.project_name}-${var.environment}-${var.tier}-secrets-"
  role        = aws_iam_role.instance.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "secretsmanager:GetSecretValue"
      Resource = var.secret_arn
    }]
  })
}

resource "aws_iam_instance_profile" "instance" {
  name_prefix = "${var.project_name}-${var.environment}-${var.tier}-"
  role        = aws_iam_role.instance.name
}

########################################
# Launch template
########################################
resource "aws_launch_template" "main" {
  name_prefix            = "${var.project_name}-${var.environment}-${var.tier}-"
  image_id               = var.ami_id
  instance_type          = var.instance_type
  vpc_security_group_ids = [var.security_group_id]
  user_data              = var.user_data

  iam_instance_profile {
    arn = aws_iam_instance_profile.instance.arn
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required" # IMDSv2
    http_put_response_hop_limit = 2
  }

  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_size = 20
      volume_type = "gp3"
      encrypted   = true
    }
  }

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "${var.project_name}-${var.environment}-${var.tier}"
      Tier = var.tier
    }
  }

  lifecycle {
    create_before_destroy = true
  }
}

########################################
# Auto Scaling Group
# Fix: version references computed latest_version (int),
# not the "$Latest" string — forces Terraform to see a
# diff whenever the template updates, triggering refresh.
########################################
resource "aws_autoscaling_group" "main" {
  name_prefix         = "${var.project_name}-${var.environment}-${var.tier}-"
  vpc_zone_identifier = var.subnet_ids
  target_group_arns   = [var.target_group_arn]

  min_size         = var.asg_min_size
  max_size         = var.asg_max_size
  desired_capacity = var.asg_desired_capacity

  health_check_type         = "ELB"
  health_check_grace_period = 300

  launch_template {
    id      = aws_launch_template.main.id
    version = aws_launch_template.main.latest_version
  }

  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = 50
      instance_warmup        = 180
    }
    triggers = ["launch_template"]
  }

  tag {
    key                 = "Name"
    value               = "${var.project_name}-${var.environment}-${var.tier}-asg"
    propagate_at_launch = false
  }

  lifecycle {
    create_before_destroy = true
  }
}

########################################
# Target-tracking scaling
########################################
resource "aws_autoscaling_policy" "cpu" {
  name                   = "${var.project_name}-${var.environment}-${var.tier}-cpu"
  autoscaling_group_name = aws_autoscaling_group.main.name
  policy_type            = "TargetTrackingScaling"

  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }
    target_value = 60.0
  }
}
