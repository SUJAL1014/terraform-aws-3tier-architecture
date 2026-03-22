# ============================================================
# modules/compute/main.tf
# Creates:
#   1. IAM role + policies    — EC2 identity and permissions
#   2. ALB                    — receives traffic from internet
#   3. Target group           — pool of EC2 instances
#   4. ALB listener           — port 80 → forward to target group
#   5. Launch template        — EC2 config + userdata.sh
#   6. Auto Scaling Group     — runs and manages EC2 instances
#   7. Scaling policies x2    — scale out / scale in
#   8. CloudWatch alarms x2   — trigger scaling policies
# ============================================================

data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }
}

# ── 1. IAM Role ───────────────────────────────────────────────
# EC2 needs an identity so it can call AWS APIs
# Without this, EC2 cannot read Secrets Manager
resource "aws_iam_role" "ec2" {
  name = "${var.project}-${var.environment}-ec2-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = { Name = "${var.project}-${var.environment}-ec2-role" }
}

# SSM policy — lets you connect to EC2 via AWS Systems Manager
# No need to open port 22 or manage SSH keys
resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.ec2.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# Custom policy — allows EC2 to read ONLY the DB secret
# Principle of least privilege — can't read any other secrets
resource "aws_iam_role_policy" "secrets_access" {
  name = "${var.project}-${var.environment}-secrets-access"
  role = aws_iam_role.ec2.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["secretsmanager:GetSecretValue"]
      Resource = var.db_secret_arn
    }]
  })
}

# Instance profile — this is what actually attaches the IAM role to EC2
resource "aws_iam_instance_profile" "ec2" {
  name = "${var.project}-${var.environment}-ec2-profile"
  role = aws_iam_role.ec2.name
}

# ── 2. Application Load Balancer ──────────────────────────────
# Sits in public subnets, receives traffic from internet
# Distributes requests across EC2 instances in private subnets
resource "aws_lb" "main" {
  name               = "${var.project}-${var.environment}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [var.sg_alb_id]
  subnets            = var.public_subnet_ids

  # Access logs help debug traffic issues
  enable_deletion_protection = false

  tags = { Name = "${var.project}-${var.environment}-alb" }
}

# ── 3. Target Group ───────────────────────────────────────────
# Pool of EC2 instances that receive traffic from the ALB
# ALB removes unhealthy instances from the pool automatically
resource "aws_lb_target_group" "app" {
  name     = "${var.project}-${var.environment}-tg"
  port     = var.app_port
  protocol = "HTTP"
  vpc_id   = var.vpc_id

  health_check {
    path                = "/health"    # Node.js /health endpoint
    healthy_threshold   = 2            # 2 passing checks = healthy
    unhealthy_threshold = 3            # 3 failing checks = unhealthy
    interval            = 30           # check every 30 seconds
    timeout             = 5            # fail if no response in 5s
    matcher             = "200"        # expect HTTP 200
  }

  tags = { Name = "${var.project}-${var.environment}-tg" }
}

# ── 4. ALB Listener ───────────────────────────────────────────
# Listens on port 80, forwards all traffic to the target group
# When you add your domain later, add a port 443 HTTPS listener
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}

resource "aws_launch_template" "app" {
  name_prefix   = "${var.project}-${var.environment}-lt-"
  image_id      = data.aws_ami.amazon_linux.id
  instance_type = var.instance_type

  iam_instance_profile {
    name = aws_iam_instance_profile.ec2.name
  }

  network_interfaces {
    associate_public_ip_address = false
    security_groups             = [var.sg_app_id]
  }

  user_data = base64encode(<<-EOF
    #!/bin/bash
    set -euxo pipefail

    # ── Step 1: Install system dependencies ──────────────────
    yum update -y
    yum install -y jq
    curl -fsSL https://rpm.nodesource.com/setup_20.x | bash -
    yum install -y nodejs

    # ── Step 2: Fetch DB password from Secrets Manager ───────
    # Terraform injects db_secret_arn and aws_region below
    SECRET_JSON=$(aws secretsmanager get-secret-value \
      --secret-id "${var.db_secret_arn}" \
      --region "${var.aws_region}" \
      --query SecretString \
      --output text)

    DB_PASSWORD=$(echo "$SECRET_JSON" | jq -r '.password')

    # ── Step 3: Write environment file ───────────────────────
    # Terraform injects all  values at plan time
    # Bash reads them at runtime from /etc/app.env
    cat > /etc/app.env <<APPENV
    PORT=${var.app_port}
    NODE_ENV=production
    DB_HOST=${var.db_host}
    DB_PORT=5432
    DB_NAME=${var.db_name}
    DB_USER=${var.db_username}
    DB_PASSWORD=$DB_PASSWORD
    APPENV
    chmod 600 /etc/app.env

    # ── Step 4: Write Node.js app ─────────────────────────────
    mkdir -p /opt/app

    cat > /opt/app/package.json <<PKG
    {
      "name": "taskflow-api",
      "version": "1.0.0",
      "dependencies": {
        "express": "^4.18.2",
        "pg": "^8.11.3",
        "cors": "^2.8.5"
      }
    }
    PKG

    cat > /opt/app/index.js <<APPJS
    const express = require('express');
    const { Pool } = require('pg');
    const cors    = require('cors');

    const app  = express();
    const port = process.env.PORT || 4000;

    app.use(cors());
    app.use(express.json());

    const pool = new Pool({
      host:     process.env.DB_HOST,
      port:     parseInt(process.env.DB_PORT),
      database: process.env.DB_NAME,
      user:     process.env.DB_USER,
      password: process.env.DB_PASSWORD,
      ssl:      { rejectUnauthorized: false },
    });

    app.get('/health', async (req, res) => {
      try {
        await pool.query('SELECT 1');
        res.json({ status: 'ok', db: 'connected' });
      } catch (err) {
        res.status(503).json({ status: 'error', db: 'disconnected' });
      }
    });

    app.get('/api/tasks', async (req, res) => {
      try {
        const { rows } = await pool.query(
          'SELECT * FROM tasks ORDER BY created_at DESC'
        );
        res.json(rows);
      } catch (err) {
        res.status(500).json({ error: err.message });
      }
    });

    app.post('/api/tasks', async (req, res) => {
      try {
        const { title, description = '', status = 'todo', priority = 'medium' } = req.body;
        if (!title) return res.status(400).json({ error: 'Title required' });
        const { rows } = await pool.query(
          'INSERT INTO tasks (title, description, status, priority) VALUES (\$1,\$2,\$3,\$4) RETURNING *',
          [title, description, status, priority]
        );
        res.status(201).json(rows[0]);
      } catch (err) {
        res.status(500).json({ error: err.message });
      }
    });

    app.patch('/api/tasks/:id', async (req, res) => {
      try {
        const fields  = ['title', 'description', 'status', 'priority'];
        const updates = [];
        const values  = [];
        let idx = 1;
        for (const f of fields) {
          if (req.body[f] !== undefined) {
            updates.push(f + ' = \$' + idx++);
            values.push(req.body[f]);
          }
        }
        if (!updates.length) return res.status(400).json({ error: 'No fields' });
        values.push(req.params.id);
        const { rows } = await pool.query(
          'UPDATE tasks SET ' + updates.join(', ') + ' WHERE id = \$' + idx + ' RETURNING *',
          values
        );
        if (!rows.length) return res.status(404).json({ error: 'Not found' });
        res.json(rows[0]);
      } catch (err) {
        res.status(500).json({ error: err.message });
      }
    });

    app.delete('/api/tasks/:id', async (req, res) => {
      try {
        const { rows } = await pool.query(
          'DELETE FROM tasks WHERE id = \$1 RETURNING id',
          [req.params.id]
        );
        if (!rows.length) return res.status(404).json({ error: 'Not found' });
        res.json({ deleted: rows[0].id });
      } catch (err) {
        res.status(500).json({ error: err.message });
      }
    });

    app.listen(port, () => console.log('TaskFlow API running on port ' + port));
    APPJS

    # ── Step 5: Install npm packages ─────────────────────────
    cd /opt/app && npm install --production

    # ── Step 6: Create systemd service ───────────────────────
    cat > /etc/systemd/system/app.service <<SVC
    [Unit]
    Description=TaskFlow Node.js API
    After=network.target

    [Service]
    EnvironmentFile=/etc/app.env
    ExecStart=/usr/bin/node /opt/app/index.js
    Restart=always
    RestartSec=5
    User=nobody
    WorkingDirectory=/opt/app
    StandardOutput=journal
    StandardError=journal

    [Install]
    WantedBy=multi-user.target
    SVC

    systemctl daemon-reload
    systemctl enable app
    systemctl start app

    echo "TaskFlow API started successfully"
  EOF
  )

  tag_specifications {
    resource_type = "instance"
    tags          = { Name = "${var.project}-${var.environment}-app" }
  }

  lifecycle {
    create_before_destroy = true
  }
}

# ── 6. Auto Scaling Group ─────────────────────────────────────
# Manages a pool of EC2 instances
# Automatically replaces unhealthy instances
# Scales in/out based on CloudWatch alarms below
resource "aws_autoscaling_group" "app" {
  name                = "${var.project}-${var.environment}-asg"
  vpc_zone_identifier = var.private_app_subnet_ids
  target_group_arns   = [aws_lb_target_group.app.arn]

  # Use ELB health checks — if ALB marks instance unhealthy,
  # ASG terminates it and launches a replacement
  health_check_type         = "ELB"
  health_check_grace_period = 120  # wait 2 min after launch before checking

  min_size         = var.asg_min
  max_size         = var.asg_max
  desired_capacity = var.asg_desired

  launch_template {
    id      = aws_launch_template.app.id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "${var.project}-${var.environment}-app"
    propagate_at_launch = true
  }
}

# ── 7. Scaling Policies ───────────────────────────────────────
# scale_out → add 1 instance when CPU is high
resource "aws_autoscaling_policy" "scale_out" {
  name                   = "${var.project}-${var.environment}-scale-out"
  autoscaling_group_name = aws_autoscaling_group.app.name
  adjustment_type        = "ChangeInCapacity"
  scaling_adjustment     = 1
  cooldown               = 300  # wait 5 min before scaling again
}

# scale_in → remove 1 instance when CPU is low
resource "aws_autoscaling_policy" "scale_in" {
  name                   = "${var.project}-${var.environment}-scale-in"
  autoscaling_group_name = aws_autoscaling_group.app.name
  adjustment_type        = "ChangeInCapacity"
  scaling_adjustment     = -1
  cooldown               = 300
}

# ── 8. CloudWatch Alarms ──────────────────────────────────────
# cpu_high → triggers scale_out policy
resource "aws_cloudwatch_metric_alarm" "cpu_high" {
  alarm_name          = "${var.project}-${var.environment}-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2       # must be high for 2 consecutive periods
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 120     # each period = 2 minutes
  statistic           = "Average"
  threshold           = var.cpu_scale_out_threshold
  alarm_actions       = [aws_autoscaling_policy.scale_out.arn]
  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.app.name
  }
}

# cpu_low → triggers scale_in policy
resource "aws_cloudwatch_metric_alarm" "cpu_low" {
  alarm_name          = "${var.project}-${var.environment}-cpu-low"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 3       # must be low for 3 consecutive periods
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 120
  statistic           = "Average"
  threshold           = var.cpu_scale_in_threshold
  alarm_actions       = [aws_autoscaling_policy.scale_in.arn]
  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.app.name
  }
}