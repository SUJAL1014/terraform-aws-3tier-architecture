output "sg_alb_id" {
  description = "ALB security group ID — passed to compute module"
  value       = aws_security_group.sg-alb.id
}

output "sg_app_id" {
  description = "EC2 security group ID — passed to compute module"
  value       = aws_security_group.sg-app.id
}

output "sg_db_id" {
  description = "RDS security group ID — passed to database module"
  value       = aws_security_group.sg-db.id
}