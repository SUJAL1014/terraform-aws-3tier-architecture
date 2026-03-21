
resource "aws_security_group" "sg-alb" {
  name        = "${var.project}-${var.environment}-sg-alb"
  description = "Allow HTTP and HTTPS from internet"
  vpc_id      = var.vpc_id

  # Allow inbound HTTP from anywhere
  ingress {
    description = "HTTP from internet"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow inbound HTTPS from anywhere
  ingress {
    description = "HTTPS from internet"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow all outbound — ALB needs to forward to EC2
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project}-${var.environment}-sg-alb" }
}


resource "aws_security_group" "sg-app" {
  name        = "${var.project}-${var.environment}-sg-app"
  description = "Allow inbound only from ALB security group"
  vpc_id      = var.vpc_id

  # Only allow traffic on app_port and only from the ALB sg
  # This means nobody can reach EC2 directly from the internet
  ingress {
    description     = "App port from ALB only"
    from_port       = var.app_port
    to_port         = var.app_port
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  # Allow all outbound — EC2 needs to reach RDS and Secrets Manager
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project}-${var.environment}-sg-app" }
}


resource "aws_security_group" "sg-db" {
  name        = "${var.project}-${var.environment}-sg-db"
  description = "Allow inbound only from EC2 security group"
  vpc_id      = var.vpc_id

  # Only allow PostgreSQL port and only from the EC2 sg
  # RDS is completely unreachable from internet or ALB
  ingress {
    description     = "PostgreSQL from EC2 only"
    from_port       = var.db_port
    to_port         = var.db_port
    protocol        = "tcp"
    security_groups = [aws_security_group.app.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project}-${var.environment}-sg-db" }
}