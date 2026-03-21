# ============================================================
# modules/database/variables.tf
# ============================================================

variable "project" {
  description = "Project name prefix"
  type        = string
}

variable "environment" {
  description = "dev / staging / prod"
  type        = string
}

variable "private_db_subnet_ids" {
  description = "Private DB subnet IDs — from module.networking.private_db_subnet_ids"
  type        = list(string)
}

variable "sg_db_id" {
  description = "RDS security group ID — from module.security.sg_db_id"
  type        = string
}

variable "db_name" {
  description = "PostgreSQL database name"
  type        = string
  default     = "taskdb"
}

variable "db_username" {
  description = "PostgreSQL master username"
  type        = string
  sensitive   = true
}

variable "db_password" {
  description = "PostgreSQL master password"
  type        = string
  sensitive   = true
}

variable "db_port" {
  description = "PostgreSQL port"
  type        = number
  default     = 5432
}

variable "db_instance_class" {
  description = "RDS instance size"
  type        = string
  default     = "db.t3.micro"
}

variable "multi_az" {
  description = "Enable Multi-AZ standby — true for staging/prod, false for dev"
  type        = bool
  default     = false
}

variable "deletion_protection" {
  description = "Prevent accidental deletion — true for prod only"
  type        = bool
  default     = false
}