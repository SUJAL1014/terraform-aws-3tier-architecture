# ============================================================
# modules/database/main.tf
# Creates:
#   1. Secrets Manager secret  — stores DB credentials as JSON
#   2. Secret version          — the actual credential values
#   3. DB subnet group         — tells RDS which subnets to use
#   4. RDS PostgreSQL instance — Multi-AZ, encrypted, private
# ============================================================

# ── 1. Secrets Manager secret ─────────────────────────────────
# Stores DB credentials as JSON so EC2 can fetch them securely
# EC2 never has the password hardcoded — it reads from here
resource "aws_secretsmanager_secret" "db" {
  name        = "${var.project}-${var.environment}-db-credentials"

  # Keep secret for 7 days after deletion before permanent removal
  # Gives you time to recover if deleted accidentally
  recovery_window_in_days = 7

  tags = { Name = "${var.project}-${var.environment}-db-secret" }
}

# ── 2. Secret version — the actual JSON values ────────────────
# Stored as JSON so EC2 can parse individual fields with jq
# Example: SECRET=$(aws secretsmanager get-secret-value ...)
#          DB_PASSWORD=$(echo $SECRET | jq -r '.password')
resource "aws_secretsmanager_secret_version" "db" {
  secret_id = aws_secretsmanager_secret.db.id

  secret_string = jsonencode({
    username = var.db_username
    password = var.db_password
    dbname   = var.db_name
    port     = var.db_port
    host     = aws_db_instance.main.address
  })

  # RDS must exist before we can write its address into the secret
  depends_on = [aws_db_instance.main]
}

# ── 3. DB subnet group ────────────────────────────────────────
# RDS requires a subnet group that spans at least 2 AZs
# This tells RDS to place the primary in AZ-a and standby in AZ-b
resource "aws_db_subnet_group" "main" {
  name       = "${var.project}-${var.environment}-db-subnet-group"
  subnet_ids = var.private_db_subnet_ids

  tags = { Name = "${var.project}-${var.environment}-db-subnet-group" }
}

# ── 4. RDS PostgreSQL instance ────────────────────────────────
resource "aws_db_instance" "main" {
  identifier     = "${var.project}-${var.environment}-rds"

  # Engine
  engine         = "postgres"
  engine_version = "15.4"

  # Size and storage
  instance_class        = var.db_instance_class
  allocated_storage     = 20
  max_allocated_storage = 100   # auto-scale storage up to 100GB
  storage_type          = "gp3"
  storage_encrypted     = true  # always encrypt at rest

  # Credentials
  db_name  = var.db_name
  username = var.db_username
  password = var.db_password

  # Network — place in private DB subnets, attach DB security group
  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [var.sg_db_id]
  publicly_accessible    = false  # never expose RDS to internet

  # High availability
  # multi_az = true  → AWS creates a standby in the second AZ
  # If primary fails, DNS automatically flips to standby in ~60s
  multi_az = var.multi_az

  # Backups
  backup_retention_period = 7             # keep 7 days of backups
  backup_window           = "03:00-04:00" # take backup at 3am UTC
  maintenance_window      = "sun:04:00-sun:05:00"

  # Deletion safety
  deletion_protection       = var.deletion_protection
  skip_final_snapshot       = false
  final_snapshot_identifier = "${var.project}-${var.environment}-final-snapshot"

  tags = { Name = "${var.project}-${var.environment}-rds" }
}