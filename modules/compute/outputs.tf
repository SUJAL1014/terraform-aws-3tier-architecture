# ============================================================
# modules/compute/outputs.tf
# alb_url and alb_dns_name printed after terraform apply
# ============================================================

output "alb_url" {
  description = "API base URL — set as VITE_API_URL in React app"
  value       = "http://${aws_lb.main.dns_name}"
}

output "alb_dns_name" {
  description = "Raw ALB DNS — add as CNAME for api.yourdomain.com in Cloudflare later"
  value       = aws_lb.main.dns_name
}

output "asg_name" {
  description = "ASG name — useful for debugging scaling events"
  value       = aws_autoscaling_group.app.name
}

output "launch_template_id" {
  description = "Launch template ID"
  value       = aws_launch_template.app.id
}