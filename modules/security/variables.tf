variable "project" {
  description = "Project name prefix"
  type        = string
}

variable "environment" {
  description = "dev / staging / prod"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID — from module.networking.vpc_id"
  type        = string
}

variable "app_port" {
  description = "Port Node.js listens on — ALB forwards to this port"
  type        = number
  default     = 4000
}

variable "db_port" {
  description = "PostgreSQL port — only EC2 can reach RDS on this"
  type        = number
  default     = 5432
}