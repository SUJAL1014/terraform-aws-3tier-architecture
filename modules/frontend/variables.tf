# ============================================================
# modules/frontend/variables.tf
# ============================================================

variable "project" {
  description = "Project name prefix"
  type        = string
}

variable "environment" {
  description = "dev / staging / prod"
  type        = string
}

variable "price_class" {
  description = "CloudFront price class — controls which edge locations are used"
  type        = string
  default     = "PriceClass_100"
  # PriceClass_100 → US, Canada, Europe only       (cheapest)
  # PriceClass_200 → + Asia, Middle East, Africa   (mid)
  # PriceClass_All → all edge locations worldwide  (most expensive)
}

variable "default_ttl" {
  description = "Default cache TTL in seconds for CloudFront"
  type        = number
  default     = 86400  # 1 day
}

variable "min_ttl" {
  description = "Minimum cache TTL in seconds"
  type        = number
  default     = 0
}

variable "max_ttl" {
  description = "Maximum cache TTL in seconds"
  type        = number
  default     = 31536000  # 1 year
}

variable "alb_dns_name" {
  description = "ALB DNS name — used as CloudFront API origin"
  type        = string
}