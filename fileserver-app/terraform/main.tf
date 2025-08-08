# main.tf
terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "FileServer-Lab"
      Environment = var.environment
      ManagedBy   = "Terraform"
    }
  }
}

# Data sources
data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
}


# Locals
locals {
  azs = slice(data.aws_availability_zones.available.names, 0, 2)
}

# VPC Module
module "vpc" {
  source = "./modules/vpc"

  project_name = var.project_name
  environment  = var.environment
  azs          = local.azs
}

# Security Groups Module
module "security" {
  source = "./modules/security"

  vpc_id       = module.vpc.vpc_id
  project_name = var.project_name
  environment  = var.environment
  allowed_cidr = var.allowed_cidr
}

# IAM Module
module "iam" {
  source = "./modules/iam"

  project_name  = var.project_name
  environment   = var.environment
  s3_bucket_arn = module.s3.bucket_arn
}

# S3 Module
module "s3" {
  source = "./modules/s3"

  project_name = var.project_name
  environment  = var.environment
}

# RDS Module
module "rds" {
  source = "./modules/rds"

  vpc_id             = module.vpc.vpc_id
  private_subnet_ids = module.vpc.private_subnet_ids
  security_group_id  = module.security.database_sg_id
  project_name       = var.project_name
  environment        = var.environment
}

# Bastion Module
module "bastion" {
  source = "./modules/bastion"

  vpc_id            = module.vpc.vpc_id
  public_subnet_id  = module.vpc.public_subnet_ids[0]
  security_group_id = module.security.bastion_sg_id
  project_name      = var.project_name
  environment       = var.environment
  ami_id            = data.aws_ami.amazon_linux.id
}

# ALB Module
module "alb" {
  source = "./modules/alb"

  vpc_id            = module.vpc.vpc_id
  public_subnet_ids = module.vpc.public_subnet_ids
  security_group_id = module.security.alb_sg_id
  project_name      = var.project_name
  environment       = var.environment
}

# Auto Scaling Module
module "autoscaling" {
  source = "./modules/autoscaling"

  vpc_id               = module.vpc.vpc_id
  private_subnet_ids   = module.vpc.private_subnet_ids
  security_group_id    = module.security.web_sg_id
  target_group_arn     = module.alb.target_group_arn
  iam_instance_profile = module.iam.instance_profile_name
  s3_bucket_name       = module.s3.bucket_name
  db_host              = module.rds.db_endpoint
  db_name              = module.rds.db_name
  db_username          = module.rds.db_username
  db_password          = module.rds.db_password
  project_name         = var.project_name
  environment          = var.environment
  ami_id               = data.aws_ami.amazon_linux.id
  app_server_ip        = module.app_server.private_ip
}

# App Server Module
module "app_server" {
  source = "./modules/app_server"

  vpc_id               = module.vpc.vpc_id
  private_subnet_id    = module.vpc.private_subnet_ids[0]
  security_group_id    = module.security.app_sg_id
  iam_instance_profile = module.iam.instance_profile_name
  s3_bucket_name       = module.s3.bucket_name
  db_host              = module.rds.db_endpoint
  db_name              = module.rds.db_name
  db_username          = module.rds.db_username
  db_password          = module.rds.db_password
  project_name         = var.project_name
  environment          = var.environment
  ami_id               = data.aws_ami.amazon_linux.id
}

# CloudWatch Module
module "cloudwatch" {
  source = "./modules/cloudwatch"

  project_name = var.project_name
  environment  = var.environment

  autoscaling_group_name = module.autoscaling.autoscaling_group_name
  app_instance_id        = module.app_server.instance_id
}

