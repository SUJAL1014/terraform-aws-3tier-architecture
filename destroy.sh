
set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

TF_DIR="/home/sujal-dedaniya/Devops/3-TIer-IaC"
ENV=${1:-dev}

echo ""
echo "============================================"
echo "   TaskFlow — Destroy Resources"
echo "   Environment: $ENV"
echo "============================================"
echo ""

if [ -z "$TF_VAR_db_password" ]; then
  read -sp "  Enter DB password: " TF_VAR_db_password
  echo ""
  export TF_VAR_db_password
fi

cd $TF_DIR

echo -e "${RED}WARNING: This will destroy ALL resources for $ENV${NC}"
read -p "  Are you sure? (yes/no): " CONFIRM

if [ "$CONFIRM" != "yes" ]; then
  echo "Cancelled."
  exit 0
fi

terraform destroy \
  -var-file="environments/$ENV.tfvars" \
  -auto-approve

echo ""
echo "============================================"
echo -e "${GREEN}   All $ENV resources destroyed${NC}"
echo "============================================"
echo ""
