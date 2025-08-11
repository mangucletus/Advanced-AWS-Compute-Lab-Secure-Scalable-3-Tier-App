# modules/app_server/main.tf

# Key Pair for App server
resource "aws_key_pair" "app" {
  key_name   = "${var.project_name}-${var.environment}-app-key"
  public_key = file("~/.ssh/id_rsa.pub")
  
  tags = {
    Name = "${var.project_name}-${var.environment}-app-key"
  }
}

# App Server Instance
resource "aws_instance" "app" {
  ami                    = var.ami_id
  instance_type          = "t3.small"
  key_name              = aws_key_pair.app.key_name
  vpc_security_group_ids = [var.security_group_id]
  subnet_id             = var.private_subnet_id
  iam_instance_profile  = var.iam_instance_profile

  user_data = base64encode(templatefile("${path.module}/user_data.sh", {
    project_name   = var.project_name
    environment    = var.environment
    s3_bucket_name = var.s3_bucket_name
    db_host       = var.db_host
    db_name       = var.db_name
    db_username   = var.db_username
    db_password   = var.db_password
  }))

  tags = {
    Name        = "${var.project_name}-${var.environment}-app-server"
    Tier        = "app"
    Project     = var.project_name
    Environment = var.environment
  }

  lifecycle {
    create_before_destroy = true
  }
}



