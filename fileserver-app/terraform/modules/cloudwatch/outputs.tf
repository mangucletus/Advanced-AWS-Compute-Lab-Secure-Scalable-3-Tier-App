# modules/cloudwatch/outputs.tf
output "dashboard_url" {
  description = "URL of the CloudWatch dashboard"
  value       = "https://eu-central-1.console.aws.amazon.com/cloudwatch/home?region=eu-central-1#dashboards:name=${aws_cloudwatch_dashboard.main.dashboard_name}"
}

output "sns_topic_arn" {
  description = "ARN of the SNS topic for alerts"
  value       = aws_sns_topic.alerts.arn
}

output "log_group_names" {
  description = "Names of the CloudWatch log groups"
  value = {
    app_logs     = aws_cloudwatch_log_group.app_logs.name
    nginx_access = aws_cloudwatch_log_group.nginx_access.name
    nginx_error  = aws_cloudwatch_log_group.nginx_error.name
    bastion_logs = aws_cloudwatch_log_group.bastion_logs.name
  }
}