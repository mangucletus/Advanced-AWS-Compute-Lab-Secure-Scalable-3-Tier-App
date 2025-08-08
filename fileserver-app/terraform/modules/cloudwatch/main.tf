# modules/cloudwatch/main.tf

# CloudWatch Log Groups
resource "aws_cloudwatch_log_group" "app_logs" {
  name              = "/aws/ec2/app/fileserver"
  retention_in_days = 14

  tags = {
    Name        = "${var.project_name}-${var.environment}-app-logs"
    Project     = var.project_name
    Environment = var.environment
  }
}

resource "aws_cloudwatch_log_group" "nginx_access" {
  name              = "/aws/ec2/nginx/access"
  retention_in_days = 14

  tags = {
    Name        = "${var.project_name}-${var.environment}-nginx-access-logs"
    Project     = var.project_name
    Environment = var.environment
  }
}

resource "aws_cloudwatch_log_group" "nginx_error" {
  name              = "/aws/ec2/nginx/error"
  retention_in_days = 14

  tags = {
    Name        = "${var.project_name}-${var.environment}-nginx-error-logs"
    Project     = var.project_name
    Environment = var.environment
  }
}

resource "aws_cloudwatch_log_group" "bastion_logs" {
  name              = "/aws/ec2/bastion"
  retention_in_days = 14

  tags = {
    Name        = "${var.project_name}-${var.environment}-bastion-logs"
    Project     = var.project_name
    Environment = var.environment
  }
}

# CloudWatch Dashboard
resource "aws_cloudwatch_dashboard" "main" {
  dashboard_name = "${var.project_name}-${var.environment}-dashboard"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 12
        height = 6

        properties = {
          metrics = [
            ["AWS/EC2", "CPUUtilization", "AutoScalingGroupName", var.autoscaling_group_name],
            [".", ".", "InstanceId", var.app_instance_id]
          ]
          period = 300
          stat   = "Average"
          region = "eu-central-1"
          title  = "EC2 CPU Utilization"
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 6
        width  = 12
        height = 6

        properties = {
          metrics = [
            ["CWAgent", "mem_used_percent", "InstanceId", var.app_instance_id],
          ]
          period = 300
          stat   = "Average"
          region = "eu-central-1"
          title  = "Memory Utilization"
        }
      },
      {
        type   = "log"
        x      = 0
        y      = 12
        width  = 24
        height = 6

        properties = {
          query = "SOURCE '/aws/ec2/app/fileserver'\n| fields @timestamp, @message\n| sort @timestamp desc\n| limit 100"
          region = "eu-central-1"
          title  = "Application Logs"
        }
      }
    ]
  })
}

# SNS Topic for alerts
resource "aws_sns_topic" "alerts" {
  name = "${var.project_name}-${var.environment}-alerts"

  tags = {
    Name        = "${var.project_name}-${var.environment}-alerts"
    Project     = var.project_name
    Environment = var.environment
  }
}

# CloudWatch Alarms for App Server CPU
resource "aws_cloudwatch_metric_alarm" "app_cpu_high" {
  alarm_name          = "${var.project_name}-${var.environment}-app-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = "120"
  statistic           = "Average"
  threshold           = "70"
  alarm_description   = "This metric monitors app server cpu utilization"
  alarm_actions       = [aws_sns_topic.alerts.arn]

  dimensions = {
    InstanceId = var.app_instance_id
  }

  tags = {
    Name        = "${var.project_name}-${var.environment}-app-cpu-high"
    Project     = var.project_name
    Environment = var.environment
  }
}

# CloudWatch Alarm for App Server Memory
resource "aws_cloudwatch_metric_alarm" "app_memory_high" {
  alarm_name          = "${var.project_name}-${var.environment}-app-memory-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "mem_used_percent"
  namespace           = "CWAgent"
  period              = "120"
  statistic           = "Average"
  threshold           = "80"
  alarm_description   = "This metric monitors app server memory utilization"
  alarm_actions       = [aws_sns_topic.alerts.arn]

  dimensions = {
    InstanceId = var.app_instance_id
  }

  tags = {
    Name        = "${var.project_name}-${var.environment}-app-memory-high"
    Project     = var.project_name
    Environment = var.environment
  }
}

# CloudWatch Alarm for Disk Space
resource "aws_cloudwatch_metric_alarm" "app_disk_high" {
  alarm_name          = "${var.project_name}-${var.environment}-app-disk-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "used_percent"
  namespace           = "CWAgent"
  period              = "300"
  statistic           = "Average"
  threshold           = "85"
  alarm_description   = "This metric monitors app server disk utilization"
  alarm_actions       = [aws_sns_topic.alerts.arn]

  dimensions = {
    InstanceId = var.app_instance_id
    device     = "/dev/xvda1"
    fstype     = "xfs"
    path       = "/"
  }

  tags = {
    Name        = "${var.project_name}-${var.environment}-app-disk-high"
    Project     = var.project_name
    Environment = var.environment
  }
}

# Custom CloudWatch Metrics for Application Health
resource "aws_cloudwatch_log_metric_filter" "error_count" {
  name           = "${var.project_name}-${var.environment}-error-count"
  log_group_name = aws_cloudwatch_log_group.app_logs.name
  pattern        = "[timestamp, request_id, ERROR]"

  metric_transformation {
    name      = "ErrorCount"
    namespace = "FileServer/Application"
    value     = "1"
  }
}

resource "aws_cloudwatch_metric_alarm" "app_error_rate" {
  alarm_name          = "${var.project_name}-${var.environment}-app-error-rate"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "ErrorCount"
  namespace           = "FileServer/Application"
  period              = "300"
  statistic           = "Sum"
  threshold           = "10"
  alarm_description   = "This metric monitors application error rate"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  treat_missing_data  = "notBreaching"

  tags = {
    Name        = "${var.project_name}-${var.environment}-app-error-rate"
    Project     = var.project_name
    Environment = var.environment
  }
}


