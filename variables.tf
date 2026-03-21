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

variable "db_port" {
  description = "PostgreSQL port"
  type        = number
}