# TaskFlow — Three-Tier Application on AWS

A fully automated three-tier web application deployed on AWS using Terraform with a modular architecture. Built with React, Node.js, and PostgreSQL — runs locally with Docker Compose and deploys to AWS with a single script.

---

## Architecture Overview

```
                        Internet
                           │
              ┌────────────┴────────────┐
              │                         │
         CloudFront                CloudFront
        (React App)               (/api/* proxy)
              │                         │
              │                         │
           S3 Bucket              App Load Balancer
         (static files)          (public subnets)
                                         │
                                 ┌───────┴───────┐
                                 │               │
                              EC2 (AZ-a)    EC2 (AZ-b)
                           Auto Scaling Group
                           Node.js REST API
                                 │
                           ┌─────┴─────┐
                        RDS Primary  RDS Standby
                        PostgreSQL    (Multi-AZ)
                       (private DB subnets)
```

---

## Tech Stack

| Layer | Local (Docker) | Cloud (AWS) |
|---|---|---|
| Frontend | React + Vite + nginx | S3 + CloudFront |
| Backend | Node.js + Express | EC2 Auto Scaling + ALB |
| Database | PostgreSQL 15 | RDS PostgreSQL |
| Orchestration | Docker Compose | Terraform |

---

## AWS Services Used

| Service | Purpose |
|---|---|
| VPC | Private network with 6 subnets across 2 AZs |
| Internet Gateway | Public internet access for ALB |
| NAT Gateway | Outbound internet for private EC2 |
| Application Load Balancer | Distributes traffic across EC2 instances |
| EC2 + Auto Scaling Group | Runs Node.js app, scales on CPU |
| S3 | Stores React build files |
| CloudFront | CDN + HTTPS + API proxy |
| RDS PostgreSQL | Managed database with Multi-AZ |
| Secrets Manager | Stores DB credentials securely |
| IAM | EC2 roles and least-privilege policies |
| CloudWatch | CPU alarms for auto scaling |
| SSM | Connect to EC2 without SSH |

---

## Project Structure

```
.
├── 3-tier-app/                        # Application code
│   └── three-tier/
│       ├── docker-compose.yml          # Local development
│       ├── database/
│       │   └── init.sql               # PostgreSQL schema
│       ├── backend/                   # Node.js Express API
│       │   ├── Dockerfile
│       │   └── src/
│       │       ├── index.js
│       │       ├── tasks.js
│       │       └── db.js
│       └── frontend/                  # React + Vite
│           ├── Dockerfile
│           ├── nginx.conf
│           └── src/
│               ├── App.jsx
│               ├── api.js
│               └── components/
│
└── 3-TIer-IaC/                        # Terraform Infrastructure
    ├── main.tf                        # Root module — calls all modules
    ├── variables.tf                   # All input variables
    ├── outputs.tf                     # All output values
    ├── backend.tf                     # State configuration
    ├── deploy.sh                      # One-click deployment script
    ├── destroy.sh                     # One-click destroy script
    ├── environments/
    │   ├── dev.tfvars                 # Dev environment values
    │   ├── staging.tfvars             # Staging environment values
    │   └── prod.tfvars                # Prod environment values
    └── modules/
        ├── networking/                # VPC, subnets, IGW, NAT, routes
        ├── security/                  # Security groups (ALB, EC2, RDS)
        ├── frontend/                  # S3 + CloudFront distribution
        ├── compute/                   # IAM, ALB, Launch Template, ASG
        └── database/                 # RDS + Secrets Manager
```

---

## Security Design

Traffic flows in one direction only — each tier can only be reached from the tier above it:

```
Internet  →  ALB (port 80/443)         sg-alb: open to world
             ALB  →  EC2 (port 4000)   sg-app: only from sg-alb
             EC2  →  RDS (port 5432)   sg-db:  only from sg-app
```

- RDS is **never** accessible from the internet
- EC2 has **no public IP** — only reachable via ALB
- DB password stored in **Secrets Manager**, never in code or environment files
- S3 bucket is **fully private** — only CloudFront can read it via OAC
- EC2 connects to AWS APIs using **IAM role** — no access keys on the server

---

## Local Development

### Prerequisites

- Docker Desktop
- Docker Compose

### Run locally

```bash
cd 3-tier-app/three-tier

# Login to Docker Hub (required to pull images)
docker login

# Start all three tiers
docker compose up --build

# App runs at:
# Frontend  → http://localhost:3000
# Backend   → http://localhost:4000
# Database  → localhost:5432
```

### Useful local commands

```bash
# Stop containers
docker compose down

# Stop and wipe database
docker compose down -v

# View logs
docker compose logs -f backend

# Test API
curl http://localhost:4000/health
curl http://localhost:4000/api/tasks
```

---

## Cloud Deployment (AWS)

### Prerequisites

- AWS CLI configured (`aws configure`)
- Terraform >= 1.6 installed
- AWS account with sufficient permissions

### Environment differences

| Variable | dev | staging | prod |
|---|---|---|---|
| Instance type | t3.micro | t3.small | t3.medium |
| ASG min/max | 1 / 2 | 1 / 4 | 2 / 8 |
| RDS instance | db.t3.micro | db.t3.small | db.t3.medium |
| Multi-AZ | false | true | true |
| Deletion protection | false | false | true |
| CloudFront TTL | 0 (no cache) | 3600 (1hr) | 86400 (1day) |
| VPC CIDR | 10.0.0.0/16 | 10.1.0.0/16 | 10.2.0.0/16 |

### One-click deploy

```bash
cd 3-TIer-IaC

# Deploy dev environment
./deploy.sh dev

# Deploy staging
./deploy.sh staging

# Deploy prod
./deploy.sh prod
```

The script automatically:
1. Runs `terraform apply`
2. Waits for EC2 to boot and pass health check
3. Waits for SSM agent to come online
4. Creates the PostgreSQL schema via SSM
5. Builds and uploads the React app to S3
6. Invalidates CloudFront cache
7. Prints the live URL

### Manual deployment steps

```bash
# Set DB password (never in tfvars)
export TF_VAR_db_password="YourPassword123"

# Init and apply
terraform init
terraform apply -var-file="environments/dev.tfvars"

# Get outputs
terraform output
```

### One-click destroy

```bash
./destroy.sh dev
```

---

## API Endpoints

Base URL: `http://YOUR_ALB_DNS` (local) or `https://YOUR_CLOUDFRONT_URL` (cloud)

| Method | Endpoint | Description |
|---|---|---|
| GET | `/health` | Health check — returns DB connection status |
| GET | `/api/tasks` | List all tasks |
| POST | `/api/tasks` | Create a task |
| PATCH | `/api/tasks/:id` | Update a task |
| DELETE | `/api/tasks/:id` | Delete a task |

### Example requests

```bash
# Health check
curl https://YOUR_CF_URL/health

# List tasks
curl https://YOUR_CF_URL/api/tasks

# Create task
curl -X POST https://YOUR_CF_URL/api/tasks \
  -H "Content-Type: application/json" \
  -d '{"title":"Deploy to AWS","priority":"high","status":"todo"}'

# Update task status
curl -X PATCH https://YOUR_CF_URL/api/tasks/1 \
  -H "Content-Type: application/json" \
  -d '{"status":"done"}'

# Delete task
curl -X DELETE https://YOUR_CF_URL/api/tasks/1
```

---

## Database Schema

```sql
CREATE TABLE tasks (
  id          SERIAL PRIMARY KEY,
  title       VARCHAR(255) NOT NULL,
  description TEXT,
  status      VARCHAR(20) DEFAULT 'todo'
              CHECK (status IN ('todo', 'in_progress', 'done')),
  priority    VARCHAR(10) DEFAULT 'medium'
              CHECK (priority IN ('low', 'medium', 'high')),
  created_at  TIMESTAMPTZ DEFAULT NOW(),
  updated_at  TIMESTAMPTZ DEFAULT NOW()
);
```

`updated_at` is automatically set on every update via a PostgreSQL trigger.

---

## Terraform Modules

### Module dependency order

```
networking  →  outputs vpc_id, subnet IDs
    ↓
security    →  outputs sg_alb_id, sg_app_id, sg_db_id
    ↓
database    →  outputs db_host, db_secret_arn
    ↓
compute     →  uses all of the above
frontend    →  independent (S3 + CloudFront)
```

### Module inputs and outputs

**networking** — takes `vpc_cidr`, outputs `vpc_id`, `public_subnet_ids`, `private_app_subnet_ids`, `private_db_subnet_ids`

**security** — takes `vpc_id`, `app_port`, `db_port`, outputs `sg_alb_id`, `sg_app_id`, `sg_db_id`

**database** — takes subnet IDs, security group, credentials, outputs `db_host`, `db_secret_arn`

**compute** — takes subnet IDs, security groups, db outputs, outputs `alb_url`, `alb_dns_name`

**frontend** — takes `project`, `environment`, `alb_dns_name`, outputs `cloudfront_url`, `s3_bucket_name`

---

## How CloudFront + ALB HTTPS Works

The React app is served over HTTPS via CloudFront. The API calls go through CloudFront as well to avoid mixed-content browser errors:

```
Browser → https://cloudfront.net          (React app from S3)
Browser → https://cloudfront.net/api/*    (API — CloudFront proxies to ALB)
                     ↓
         CloudFront → http://ALB          (internal AWS network — HTTP is fine)
                     ↓
                   EC2 → RDS
```

This means the browser only ever sees HTTPS. CloudFront talks to ALB over HTTP internally within AWS's private network.

---

## Debugging

### Check if EC2 app started correctly

```bash
# Get instance ID
INSTANCE_ID=$(aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=taskflow-dev-app" \
  --query "Reservations[0].Instances[0].InstanceId" \
  --output text --region ap-south-1)

# Check app logs
aws ssm send-command \
  --instance-ids "$INSTANCE_ID" \
  --document-name "AWS-RunShellScript" \
  --parameters commands='["systemctl status app", "journalctl -u app -n 50"]' \
  --region ap-south-1

# Check environment file
aws ssm send-command \
  --instance-ids "$INSTANCE_ID" \
  --document-name "AWS-RunShellScript" \
  --parameters commands='["cat /etc/app.env"]' \
  --region ap-south-1
```

### Save money — stop resources overnight

```bash
# Stop EC2 instances
aws autoscaling update-auto-scaling-group \
  --auto-scaling-group-name taskflow-dev-asg \
  --min-size 0 --max-size 0 --desired-capacity 0 \
  --region ap-south-1

# Stop RDS
aws rds stop-db-instance \
  --db-instance-identifier taskflow-dev-rds \
  --region ap-south-1

# Start next day
aws autoscaling update-auto-scaling-group \
  --auto-scaling-group-name taskflow-dev-asg \
  --min-size 1 --max-size 2 --desired-capacity 1 \
  --region ap-south-1

aws rds start-db-instance \
  --db-instance-identifier taskflow-dev-rds \
  --region ap-south-1
```

---

## What I Learned

- Terraform modular architecture — splitting infrastructure into reusable, dependency-ordered modules
- AWS networking — VPC, public/private subnets, Internet Gateway, NAT Gateway, route tables
- Security groups — chain rule pattern (ALB → EC2 → RDS) with no direct internet access
- CloudFront — CDN, SPA routing fix, mixed-content solution by proxying API calls
- EC2 Auto Scaling — Launch Templates, health checks, CPU-based scaling policies
- RDS — managed PostgreSQL, Multi-AZ failover, encrypted storage
- Secrets Manager — secure credential storage, EC2 IAM role access
- SSM Session Manager — connect to private EC2 without SSH keys or bastion host
- Docker Compose — local three-tier development environment
- CI/CD ready structure — environment-specific tfvars, modular Terraform, deploy scripts

---

## Author

**Sujal Dedaniya**  
DevOps Engineer  
[GitHub](https://github.com/SUJAL1014)
