# ============================================================
# modules/database/outputs.tf
# Only reference resources created IN THIS module
# Never reference other modules here — that belongs in root
# ============================================================

output "db_host" {
  description = "RDS endpoint — passed to compute module"
  value       = aws_db_instance.main.address
  sensitive   = true
}

output "db_port" {
  description = "RDS port"
  value       = aws_db_instance.main.port
}

output "db_secret_arn" {
  description = "Secrets Manager ARN — compute module uses this in IAM policy"
  value       = aws_secretsmanager_secret.db.arn
}

output "rds_id" {
  description = "RDS instance ID"
  value       = aws_db_instance.main.id
}