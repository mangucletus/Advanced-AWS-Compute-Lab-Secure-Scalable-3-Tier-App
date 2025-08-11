# modules/bastion/main.tf

# Key Pair for Bastion Host
resource "aws_key_pair" "bastion" {
  key_name   = "${var.project_name}-${var.environment}-bastion-key"
  public_key = file("~/.ssh/id_rsa.pub") # Make sure this file exists or create it
  
  tags = {
    Name = "${var.project_name}-${var.environment}-bastion-key"
  }
}

# Bastion Host Instance
resource "aws_instance" "bastion" {
  ami                    = var.ami_id
  instance_type          = "t3.micro"
  key_name              = aws_key_pair.bastion.key_name
  vpc_security_group_ids = [var.security_group_id]
  subnet_id             = var.public_subnet_id
  
  associate_public_ip_address = true
  
  user_data = base64encode(templatefile("${path.module}/user_data.sh", {
    project_name = var.project_name
    environment  = var.environment
  }))

  tags = {
    Name = "BastionHost"
    Type = "bastion"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# Elastic IP for Bastion (optional but recommended for consistent IP)
resource "aws_eip" "bastion" {
  instance = aws_instance.bastion.id
  domain   = "vpc"
  
  tags = {
    Name = "${var.project_name}-${var.environment}-bastion-eip"
  }
  
  depends_on = [aws_instance.bastion]
}


