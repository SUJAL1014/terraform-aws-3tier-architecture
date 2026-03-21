# Networking
output "vpc_id" {
  value = module.networking.vpc_id
}

output "public_subnet_ids" {
  value = module.networking.public_subnet_ids
}

output "private_app_subnet_ids" {
  value = module.networking.private_app_subnet_ids
}

output "private_db_subnet_ids" {
  value = module.networking.private_db_subnet_ids
}

# Security
output "sg_alb_id" {
  value = module.security.sg_alb_id
}

output "sg_app_id" {
  value = module.security.sg_app_id
}

output "sg_db_id" {
  value = module.security.sg_db_id
}

# Database
output "db_secret_arn" {
  description = "Secrets Manager ARN — EC2 reads DB password from here"
  value       = module.database.db_secret_arn
}

output "rds_id" {
  description = "RDS instance ID"
  value       = module.database.rds_id
}