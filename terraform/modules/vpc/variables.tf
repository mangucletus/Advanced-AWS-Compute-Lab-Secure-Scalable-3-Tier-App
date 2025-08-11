# modules/vpc/variables.tf
variable "project_name" {
  description = "Name of the project"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "azs" {
  description = "List of availability zones"
  type        = list(string)
}