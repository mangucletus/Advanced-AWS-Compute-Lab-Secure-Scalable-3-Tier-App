# Outputs
output "alb_dns_name" {
  description = "DNS name of the Application Load Balancer"
  value       = module.alb.dns_name
}

output "bastion_ip" {
  description = "Public IP of the Bastion Host"
  value       = module.bastion.public_ip
}

output "app_server_private_ip" {
  description = "Private IP of the App Server"
  value       = module.app_server.private_ip
}

output "database_endpoint" {
  description = "Database endpoint"
  value       = module.rds.db_endpoint
  sensitive   = true
}

output "s3_bucket_name" {
  description = "S3 bucket name"
  value       = module.s3.bucket_name
}