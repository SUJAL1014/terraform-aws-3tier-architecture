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

# Compute
output "alb_url" {
  description = "API base URL — set as VITE_API_URL in React app"
  value       = module.compute.alb_url
}

output "alb_dns_name" {
  description = "Add as CNAME for api.yourdomain.com in Cloudflare"
  value       = module.compute.alb_dns_name
}

output "asg_name" {
  value = module.compute.asg_name
}


# Frontend
output "cloudfront_url" {
  description = "React app — open in browser after apply"
  value       = module.frontend.cloudfront_url
}

output "cloudfront_domain" {
  description = "Add as CNAME for yourdomain.com in Cloudflare when ready"
  value       = module.frontend.cloudfront_domain
}

output "cloudfront_distribution_id" {
  value = module.frontend.cloudfront_distribution_id
}

output "s3_bucket_name" {
  description = "Upload frontend/dist/ here to deploy React app"
  value       = module.frontend.s3_bucket_name
}

output "s3_deploy_command" {
  description = "Run this after npm run build to deploy frontend"
  value       = module.frontend.s3_deploy_command
}
