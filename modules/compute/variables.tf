# ============================================================
# modules/compute/variables.tf
# ============================================================

variable "project" {
  description = "Project name prefix"
  type        = string
}

variable "environment" {
  description = "dev / staging / prod"
  type        = string
}

variable "aws_region" {
  description = "AWS region"
  type        = string
}

# ── Networking inputs (from networking module) ────────────────
variable "public_subnet_ids" {
  description = "Public subnet IDs — ALB is placed here"
  type        = list(string)
}

variable "private_app_subnet_ids" {
  description = "Private app subnet IDs — EC2 instances are placed here"
  type        = list(string)
}

variable "vpc_id" {
  description = "VPC ID — needed for target group"
  type        = string
}

# ── Security inputs (from security module) ────────────────────
variable "sg_alb_id" {
  description = "ALB security group ID"
  type        = string
}

variable "sg_app_id" {
  description = "EC2 security group ID"
  type        = string
}

# ── Database inputs (from database module) ────────────────────
variable "db_host" {
  description = "RDS endpoint — injected into EC2 via userdata"
  type        = string
  sensitive   = true
}

variable "db_name" {
  description = "PostgreSQL database name"
  type        = string
}

variable "db_username" {
  description = "PostgreSQL master username"
  type        = string
  sensitive   = true
}

variable "db_secret_arn" {
  description = "Secrets Manager ARN — EC2 IAM policy allows reading this"
  type        = string
}

# ── App config ────────────────────────────────────────────────
variable "app_port" {
  description = "Port Node.js listens on"
  type        = number
  default     = 4000
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.micro"
}

variable "asg_min" {
  description = "Minimum EC2 instances in ASG"
  type        = number
  default     = 1
}

variable "asg_max" {
  description = "Maximum EC2 instances in ASG"
  type        = number
  default     = 4
}

variable "asg_desired" {
  description = "Desired EC2 instances at launch"
  type        = number
  default     = 1
}

variable "cpu_scale_out_threshold" {
  description = "CPU % that triggers scale out"
  type        = number
  default     = 70
}

variable "cpu_scale_in_threshold" {
  description = "CPU % that triggers scale in"
  type        = number
  default     = 30
}