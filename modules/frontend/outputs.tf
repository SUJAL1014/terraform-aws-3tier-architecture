# ============================================================
# modules/frontend/outputs.tf
# ============================================================

output "cloudfront_url" {
  description = "React app live URL — open this in your browser after apply"
  value       = "https://${aws_cloudfront_distribution.frontend.domain_name}"
}

output "cloudfront_domain" {
  description = "Raw CloudFront domain — add as CNAME for yourdomain.com in Cloudflare later"
  value       = aws_cloudfront_distribution.frontend.domain_name
}

output "cloudfront_distribution_id" {
  description = "Needed to invalidate cache after deploying new frontend build"
  value       = aws_cloudfront_distribution.frontend.id
}

output "s3_bucket_name" {
  description = "Upload your React dist/ folder here to deploy"
  value       = aws_s3_bucket.frontend.bucket
}

output "s3_bucket_arn" {
  description = "S3 bucket ARN"
  value       = aws_s3_bucket.frontend.arn
}

output "s3_deploy_command" {
  description = "Run this from project root after npm run build"
  value       = "aws s3 sync ./frontend/dist s3://${aws_s3_bucket.frontend.bucket} --delete && aws cloudfront create-invalidation --distribution-id ${aws_cloudfront_distribution.frontend.id} --paths '/*'"
}