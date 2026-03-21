variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "ap-south-1"
}

variable "project" {
  description = "Project name — used as prefix on every resource"
  type        = string
  default     = "taskflow"
}

variable "environment" {
  description = "dev / staging / prod"
  type        = string
  default     = "dev"
}


variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
}

variable "app_port" {
  description = "Port Node.js listens on inside EC2"
  type        = number
}

variable "db_instance_class" {
  type    = string
  default = "db.t3.micro"
}

variable "db_name" {
  type    = string
  default = "taskdb"
}

variable "db_username" {
  type      = string
  default   = "dbadmin"
  sensitive = true
}

variable "db_password" {
  description = "Set via: export TF_VAR_db_password=yourpassword"
  type        = string
  sensitive   = true
}

variable "db_port" {
  type    = number
  default = 5432
}

# ── NEW: db behaviour per environment ────────────────────────
variable "multi_az" {
  description = "false for dev (save cost), true for staging/prod"
  type        = bool
  default     = false
}

variable "deletion_protection" {
  description = "false for dev/staging, true for prod"
  type        = bool
  default     = false
}