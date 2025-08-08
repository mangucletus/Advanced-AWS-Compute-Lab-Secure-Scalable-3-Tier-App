# Variables
variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "eu-central-1"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "dev"
}

variable "project_name" {
  description = "Project name"
  type        = string
  default     = "fileserver"
}

variable "allowed_cidr" {
  description = "CIDR block allowed to access bastion"
  type        = string
  default     = "0.0.0.0/0" # Replace with your IP for security
}