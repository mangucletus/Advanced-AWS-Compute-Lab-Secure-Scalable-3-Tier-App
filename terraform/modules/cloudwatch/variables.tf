# modules/cloudwatch/variables.tf
variable "project_name" {
  description = "Name of the project"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "autoscaling_group_name" {
  description = "Name of the Auto Scaling Group"
  type        = string
}

variable "app_instance_id" {
  description = "ID of the app server instance"
  type        = string
}
