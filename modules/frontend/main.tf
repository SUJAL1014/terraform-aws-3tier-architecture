# ============================================================
# modules/frontend/main.tf
# Creates:
#   1. random_id              — makes S3 bucket name globally unique
#   2. aws_s3_bucket          — stores React dist/ files
#   3. public_access_block    — makes bucket fully private
#   4. versioning             — enables rollback of bad deploys
#   5. OAC                    — CloudFront identity to read S3
#   6. bucket_policy          — only allows CloudFront OAC to read
#   7. cloudfront_distribution— CDN + HTTPS + SPA routing fix
# ============================================================

# ── 1. Random ID — S3 bucket names must be globally unique ───
# Two people both named "taskflow" can't use the same bucket name
# random_id adds a short hex suffix to prevent collisions
resource "random_id" "suffix" {
  byte_length = 4
}

# ── 2. S3 Bucket — stores the React dist/ build ──────────────
resource "aws_s3_bucket" "frontend" {
  bucket        = "${var.project}-${var.environment}-frontend-${random_id.suffix.hex}"
  force_destroy = true  # allows terraform destroy to empty + delete bucket

  tags = { Name = "${var.project}-${var.environment}-frontend" }
}

# ── 3. Block all public access ────────────────────────────────
# S3 bucket is 100% private
# Only CloudFront can read from it via OAC policy below
# Nobody can access S3 directly — not even with the bucket URL
resource "aws_s3_bucket_public_access_block" "frontend" {
  bucket = aws_s3_bucket.frontend.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ── 4. Versioning — keep history of uploaded files ───────────
# If you deploy a broken build, you can restore the previous version
# from the S3 console without redeploying
resource "aws_s3_bucket_versioning" "frontend" {
  bucket = aws_s3_bucket.frontend.id

  versioning_configuration {
    status = "Enabled"
  }
}

# ── 5. Origin Access Control ──────────────────────────────────
# OAC is the identity CloudFront uses to authenticate with S3
# Without this, CloudFront cannot read from the private bucket
# This replaces the older OAI (Origin Access Identity) method
resource "aws_cloudfront_origin_access_control" "frontend" {
  name                              = "${var.project}-${var.environment}-oac"
  description                       = "OAC for ${var.project} ${var.environment} frontend"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# ── 6. S3 Bucket Policy — only allow CloudFront OAC ──────────
# This policy says: only CloudFront (identified by OAC) can read
# objects from this bucket. Everyone else gets 403 Forbidden.
resource "aws_s3_bucket_policy" "frontend" {
  bucket = aws_s3_bucket.frontend.id

  # depends_on ensures public access block is set BEFORE policy
  # Without this, Terraform sometimes applies policy before block
  # which causes an error
  depends_on = [aws_s3_bucket_public_access_block.frontend]

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowCloudFrontOACOnly"
        Effect = "Allow"
        Principal = {
          Service = "cloudfront.amazonaws.com"
        }
        Action   = "s3:GetObject"
        Resource = "${aws_s3_bucket.frontend.arn}/*"
        Condition = {
          StringEquals = {
            # Only THIS specific CloudFront distribution can read
            # Other CloudFront distributions cannot access this bucket
            "AWS:SourceArn" = aws_cloudfront_distribution.frontend.arn
          }
        }
      }
    ]
  })
}

# ── 7. CloudFront Distribution ────────────────────────────────
resource "aws_cloudfront_distribution" "frontend" {
  enabled             = true
  default_root_object = "index.html"
  price_class         = var.price_class
  comment             = "${var.project}-${var.environment}"

  # ── Origin 1: S3 — React static files ────────────────────
  origin {
    domain_name              = aws_s3_bucket.frontend.bucket_regional_domain_name
    origin_id                = "s3-${var.project}-${var.environment}"
    origin_access_control_id = aws_cloudfront_origin_access_control.frontend.id
  }

  # ── Origin 2: ALB — Node.js API ───────────────────────────
  origin {
    domain_name = var.alb_dns_name
    origin_id   = "alb-${var.project}-${var.environment}"

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "http-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  # ── Behaviour 1: /api/* → ALB ─────────────────────────────
  ordered_cache_behavior {
    path_pattern           = "/api/*"
    target_origin_id       = "alb-${var.project}-${var.environment}"
    viewer_protocol_policy = "https-only"
    allowed_methods        = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
    cached_methods         = ["GET", "HEAD"]
    cache_policy_id          = "4135ea2d-6df8-44a3-9df3-4b5a84be39ad"
    origin_request_policy_id = "b689b0a8-53d0-40ab-baf2-68738e2966ac"
  }

  # ── Behaviour 2: /health → ALB ────────────────────────────
  ordered_cache_behavior {
    path_pattern           = "/health"
    target_origin_id       = "alb-${var.project}-${var.environment}"
    viewer_protocol_policy = "https-only"
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    cache_policy_id        = "4135ea2d-6df8-44a3-9df3-4b5a84be39ad"
  }

  # ── Default behaviour: everything else → S3 ──────────────
  default_cache_behavior {
    target_origin_id       = "s3-${var.project}-${var.environment}"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD", "OPTIONS"]
    cached_methods         = ["GET", "HEAD"]
    compress               = true
    cache_policy_id        = "658327ea-f89d-4fab-a63d-7e88639e58f6"
  }

  # React SPA routing fix
  custom_error_response {
    error_code            = 403
    response_code         = 200
    response_page_path    = "/index.html"
    error_caching_min_ttl = 0
  }

  custom_error_response {
    error_code            = 404
    response_code         = 200
    response_page_path    = "/index.html"
    error_caching_min_ttl = 0
  }

  restrictions {
    geo_restriction { restriction_type = "none" }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }

  tags = { Name = "${var.project}-${var.environment}-cf" }
}