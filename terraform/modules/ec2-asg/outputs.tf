output "asg_name" {
  description = "Auto Scaling Group name (used by deploy-app.yml for instance refresh)"
  value       = aws_autoscaling_group.main.name
}

output "asg_arn" {
  description = "Auto Scaling Group ARN"
  value       = aws_autoscaling_group.main.arn
}

output "launch_template_id" {
  description = "Launch template ID"
  value       = aws_launch_template.main.id
}

output "launch_template_latest_version" {
  description = "Launch template latest version (integer)"
  value       = aws_launch_template.main.latest_version
}

output "iam_role_arn" {
  description = "Instance IAM role ARN"
  value       = aws_iam_role.instance.arn
}

output "iam_role_name" {
  description = "Instance IAM role name"
  value       = aws_iam_role.instance.name
}

output "instance_profile_arn" {
  description = "Instance profile ARN"
  value       = aws_iam_instance_profile.instance.arn
}
