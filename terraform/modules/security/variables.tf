# modules/security/variables.tf
variable "vpc_id" {
  description = "ID of the VPC"
  type        = string
}

variable "project_name" {
  description = "Name of the project"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "allowed_cidr" {
  description = "CIDR block allowed to access bastion"
  type        = string
}

