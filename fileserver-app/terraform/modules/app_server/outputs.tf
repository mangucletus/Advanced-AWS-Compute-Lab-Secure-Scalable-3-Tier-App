# modules/app_server/outputs.tf
output "instance_id" {
  description = "ID of the app server instance"
  value       = aws_instance.app.id
}

output "private_ip" {
  description = "Private IP of the app server"
  value       = aws_instance.app.private_ip
}