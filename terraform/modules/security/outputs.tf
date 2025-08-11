# modules/security/outputs.tf
output "alb_sg_id" {
  description = "ID of the ALB security group"
  value       = aws_security_group.alb.id
}

output "web_sg_id" {
  description = "ID of the Web tier security group"
  value       = aws_security_group.web.id
}

output "app_sg_id" {
  description = "ID of the App tier security group"
  value       = aws_security_group.app.id
}

output "database_sg_id" {
  description = "ID of the Database security group"
  value       = aws_security_group.database.id
}

output "bastion_sg_id" {
  description = "ID of the Bastion security group"
  value       = aws_security_group.bastion.id
}