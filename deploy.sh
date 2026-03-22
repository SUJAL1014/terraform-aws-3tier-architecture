
set -e

# ── Colors ────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log()     { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[DONE]${NC} $1"; }
warn()    { echo -e "${YELLOW}[WAIT]${NC} $1"; }
error()   { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# ── Config ────────────────────────────────────────────────────
TF_DIR="/home/sujal-dedaniya/Devops/3-TIer-IaC"
APP_DIR="/home/sujal-dedaniya/Devops/3-tier-app/three-tier/frontend"
REGION="ap-south-1"
ENV=${1:-dev}
ASG_NAME="taskflow-${ENV}-asg"
EC2_TAG="taskflow-${ENV}-app"

# ============================================================
echo ""
echo "============================================"
echo "   TaskFlow — Full Deployment Script"
echo "   Environment: $ENV"
echo "============================================"
echo ""

# ── Step 1: DB Password ───────────────────────────────────────
log "Step 1: Setting DB password..."
if [ -z "$TF_VAR_db_password" ]; then
  read -sp "  Enter DB password: " TF_VAR_db_password
  echo ""
  export TF_VAR_db_password
fi
success "DB password set"

# ── Step 2: Terraform Init ────────────────────────────────────
log "Step 2: Terraform init..."
cd $TF_DIR
terraform init -upgrade > /dev/null 2>&1
success "Terraform initialized"

# ── Step 3: Terraform Apply ───────────────────────────────────
log "Step 3: Terraform apply (10-15 minutes)..."
terraform apply \
  -var-file="environments/$ENV.tfvars" \
  -auto-approve
success "Infrastructure deployed"

# ── Step 4: Save Outputs ──────────────────────────────────────
log "Step 4: Saving terraform outputs..."
CF_URL=$(terraform output -raw cloudfront_url)
CF_ID=$(terraform output -raw cloudfront_distribution_id)
BUCKET=$(terraform output -raw s3_bucket_name)
ALB_URL=$(terraform output -raw alb_url)

echo ""
echo "  CloudFront URL : $CF_URL"
echo "  ALB URL        : $ALB_URL"
echo "  S3 Bucket      : $BUCKET"
echo ""
success "Outputs saved"

# ── Step 5: Wait for EC2 to boot ─────────────────────────────
warn "Step 5: Waiting for EC2 to boot and start Node.js..."
for i in {1..16}; do
  sleep 30
  echo -n "  waited $((i * 30)) seconds..."

  HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
    $ALB_URL/health 2>/dev/null || echo "000")

  if [ "$HTTP_CODE" = "200" ]; then
    echo ""
    success "EC2 is up and healthy!"
    break
  else
    echo " not ready yet (HTTP $HTTP_CODE)"
  fi

  if [ $i -eq 16 ]; then
    error "EC2 did not start after 8 minutes. Check AWS console."
  fi
done

# ── Step 6: Verify health check ───────────────────────────────
log "Step 6: Verifying health check..."
HEALTH=$(curl -s $ALB_URL/health)
echo "  Response: $HEALTH"

if [[ $HEALTH != *"ok"* ]]; then
  error "Health check failed: $HEALTH"
fi
success "Backend is healthy"

# ── Step 7: Get EC2 Instance ID ───────────────────────────────
log "Step 7: Getting EC2 instance ID..."
INSTANCE_ID=$(aws ec2 describe-instances \
  --filters \
    "Name=tag:Name,Values=$EC2_TAG" \
    "Name=instance-state-name,Values=running" \
  --query "Reservations[0].Instances[0].InstanceId" \
  --output text \
  --region $REGION)

if [ -z "$INSTANCE_ID" ] || [ "$INSTANCE_ID" = "None" ]; then
  error "Could not find running EC2 instance with tag: $EC2_TAG"
fi

echo "  Instance ID: $INSTANCE_ID"
success "EC2 instance found"

# ── Wait for SSM agent to be ready ────────────────────────────
log "Waiting for SSM agent to be ready..."
for i in {1..12}; do
  SSM_STATUS=$(aws ssm describe-instance-information \
    --filters "Key=InstanceIds,Values=$INSTANCE_ID" \
    --region $REGION \
    --query "InstanceInformationList[0].PingStatus" \
    --output text 2>/dev/null || echo "None")

  if [ "$SSM_STATUS" = "Online" ]; then
    success "SSM agent is ready"
    break
  fi

  echo "  SSM not ready yet ($SSM_STATUS) — waiting 30 seconds..."
  sleep 30

  if [ $i -eq 12 ]; then
    error "SSM agent did not come online after 6 minutes"
  fi
done

# ── Step 8: Run Database Schema ───────────────────────────────
log "Step 8: Creating database schema..."

COMMAND_ID=$(aws ssm send-command \
  --instance-ids "$INSTANCE_ID" \
  --document-name "AWS-RunShellScript" \
  --parameters commands='[
    "yum install -y postgresql15 2>&1 | tail -1",
    "source /etc/app.env",
    "PGPASSWORD=$DB_PASSWORD /usr/bin/psql -h $DB_HOST -U $DB_USER -d $DB_NAME -c \"CREATE TABLE IF NOT EXISTS tasks (id SERIAL PRIMARY KEY, title VARCHAR(255) NOT NULL, description TEXT, status VARCHAR(20) NOT NULL DEFAULT '"'"'todo'"'"' CHECK (status IN ('"'"'todo'"'"','"'"'in_progress'"'"','"'"'done'"'"')), priority VARCHAR(10) NOT NULL DEFAULT '"'"'medium'"'"' CHECK (priority IN ('"'"'low'"'"','"'"'medium'"'"','"'"'high'"'"')), created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(), updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW());\"",
    "PGPASSWORD=$DB_PASSWORD /usr/bin/psql -h $DB_HOST -U $DB_USER -d $DB_NAME -c \"CREATE OR REPLACE FUNCTION update_updated_at() RETURNS TRIGGER AS \\$\\$ BEGIN NEW.updated_at = NOW(); RETURN NEW; END; \\$\\$ LANGUAGE plpgsql;\"",
    "PGPASSWORD=$DB_PASSWORD /usr/bin/psql -h $DB_HOST -U $DB_USER -d $DB_NAME -c \"DROP TRIGGER IF EXISTS tasks_updated_at ON tasks; CREATE TRIGGER tasks_updated_at BEFORE UPDATE ON tasks FOR EACH ROW EXECUTE FUNCTION update_updated_at();\"",
    "PGPASSWORD=$DB_PASSWORD /usr/bin/psql -h $DB_HOST -U $DB_USER -d $DB_NAME -c \"\\dt\""
  ]' \
  --region $REGION \
  --query "Command.CommandId" \
  --output text)

echo "  Command ID: $COMMAND_ID"

warn "  Waiting 40 seconds for schema to run..."
sleep 40

# Check result with retry
for attempt in {1..3}; do
  SCHEMA_STATUS=$(aws ssm get-command-invocation \
    --command-id "$COMMAND_ID" \
    --instance-id "$INSTANCE_ID" \
    --region $REGION \
    --query "Status" \
    --output text 2>/dev/null || echo "InProgress")

  if [ "$SCHEMA_STATUS" = "Success" ] || [ "$SCHEMA_STATUS" = "Failed" ]; then
    break
  fi

  echo "  Still running... waiting 15 more seconds"
  sleep 15
done

SCHEMA_OUTPUT=$(aws ssm get-command-invocation \
  --command-id "$COMMAND_ID" \
  --instance-id "$INSTANCE_ID" \
  --region $REGION \
  --query "StandardOutputContent" \
  --output text)

SCHEMA_ERROR=$(aws ssm get-command-invocation \
  --command-id "$COMMAND_ID" \
  --instance-id "$INSTANCE_ID" \
  --region $REGION \
  --query "StandardErrorContent" \
  --output text)

echo "  Status : $SCHEMA_STATUS"
echo "  Output : $SCHEMA_OUTPUT"

if [ "$SCHEMA_STATUS" != "Success" ]; then
  echo "  Error  : $SCHEMA_ERROR"
  error "Schema creation failed"
fi
success "Database schema created"

# ── Step 9: Build React Frontend ──────────────────────────────
log "Step 9: Building React frontend..."
cd $APP_DIR

cat > .env.production <<EOF
VITE_API_URL=$CF_URL
EOF

echo "  API URL: $CF_URL"
npm install --silent
npm run build
success "Frontend built"

# ── Step 10: Deploy to S3 ─────────────────────────────────────
log "Step 10: Uploading frontend to S3..."
aws s3 sync ./dist s3://$BUCKET --delete --quiet
success "Frontend uploaded to S3"

# ── Step 11: Invalidate CloudFront ────────────────────────────
log "Step 11: Invalidating CloudFront cache..."
INVALIDATION_ID=$(aws cloudfront create-invalidation \
  --distribution-id $CF_ID \
  --paths "/*" \
  --query "Invalidation.Id" \
  --output text)

echo "  Invalidation ID: $INVALIDATION_ID"
success "CloudFront cache cleared"

# ── Step 12: Final API Test ───────────────────────────────────
log "Step 12: Final API test..."
sleep 10
TASKS=$(curl -s $ALB_URL/api/tasks)
echo "  GET /api/tasks: $TASKS"
success "API working"

# ── Done ──────────────────────────────────────────────────────
echo ""
echo "============================================"
echo -e "${GREEN}   DEPLOYMENT COMPLETE!${NC}"
echo "============================================"
echo ""
echo -e "  ${GREEN}Open this URL in your browser:${NC}"
echo ""
echo -e "  ${YELLOW}$CF_URL${NC}"
echo ""
echo "============================================"
echo ""
