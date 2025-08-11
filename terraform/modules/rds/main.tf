# modules/rds/main.tf

# Random password for database - Fixed to exclude invalid characters
resource "random_password" "db_password" {
  length  = 16
  special = true
  # Exclude characters that RDS doesn't allow: /, @, ", and space
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

# DB Subnet Group
resource "aws_db_subnet_group" "main" {
  name       = "${var.project_name}-${var.environment}-db-subnet-group"
  subnet_ids = var.private_subnet_ids

  tags = {
    Name = "${var.project_name}-${var.environment}-db-subnet-group"
  }
}

# RDS Parameter Group
resource "aws_db_parameter_group" "main" {
  family = "postgres15"
  name   = "${var.project_name}-${var.environment}-db-params"

  parameter {
    name  = "log_connections"
    value = "1"
  }

  parameter {
    name  = "log_disconnections"
    value = "1"
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-db-params"
  }
}

# RDS Instance
resource "aws_db_instance" "main" {
  identifier = "${var.project_name}-${var.environment}-database"
  
  # Engine options
  engine         = "postgres"
  engine_version = "15.13"  # Latest available minor version
  instance_class = "db.t3.micro"
  
  # Storage
  allocated_storage     = 20
  max_allocated_storage = 100
  storage_type          = "gp2"
  storage_encrypted     = true
  
  # Database configuration
  db_name  = "fileserver"
  username = "dbadmin"
  password = random_password.db_password.result
  port     = 5432
  
  # Network & Security
  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [var.security_group_id]
  parameter_group_name   = aws_db_parameter_group.main.name
  publicly_accessible    = false
  
  # Backup & Maintenance
  backup_retention_period = 7
  backup_window          = "03:00-04:00"
  maintenance_window     = "Sun:04:00-Sun:05:00"
  
  # Monitoring
  monitoring_interval = 60
  monitoring_role_arn = aws_iam_role.rds_monitoring.arn
  
  # Other options
  skip_final_snapshot       = true
  deletion_protection      = false
  auto_minor_version_upgrade = true
  
  tags = {
    Name = "${var.project_name}-${var.environment}-database"
  }
}

# IAM Role for RDS Enhanced Monitoring
resource "aws_iam_role" "rds_monitoring" {
  name = "${var.project_name}-${var.environment}-rds-monitoring-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "monitoring.rds.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "${var.project_name}-${var.environment}-rds-monitoring-role"
  }
}

resource "aws_iam_role_policy_attachment" "rds_monitoring" {
  role       = aws_iam_role.rds_monitoring.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

# Store database password in AWS Systems Manager Parameter Store
resource "aws_ssm_parameter" "db_password" {
  name  = "/${var.project_name}/${var.environment}/database/password"
  type  = "SecureString"
  value = random_password.db_password.result

  tags = {
    Name = "${var.project_name}-${var.environment}-db-password"
  }
}