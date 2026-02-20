#!/bin/bash
# switch_to_s3.sh: Switch to S3 config from Terraform output

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TERRAFORM_DIR="$PROJECT_ROOT/infra/terraform/environments/prod"

if [ ! -d "$TERRAFORM_DIR" ]; then
  echo "Error: Terraform prod directory not found: $TERRAFORM_DIR"
  exit 1
fi

cd "$TERRAFORM_DIR"

# Check if Terraform has been applied
if [ ! -f "terraform.tfstate" ] && [ ! -f ".terraform/terraform.tfstate" ]; then
  echo "Error: Terraform state not found. Run 'terraform apply' first."
  exit 1
fi

# Get Terraform outputs
BUCKET=$(terraform output -raw s3_bucket_name 2>/dev/null || echo "")
ACCESS_KEY=$(terraform output -raw s3_access_key_id 2>/dev/null || echo "")
SECRET_KEY=$(terraform output -raw s3_secret_access_key 2>/dev/null || echo "")
REGION=$(grep -E '^\s*aws_region' terraform.tfvars 2>/dev/null | sed 's/.*"\(.*\)".*/\1/' || echo "us-east-1")

if [ -z "$BUCKET" ] || [ -z "$ACCESS_KEY" ] || [ -z "$SECRET_KEY" ]; then
  echo "Error: Failed to get Terraform outputs. Make sure 'terraform apply' completed successfully."
  exit 1
fi

# Generate environment file
ENV_FILE="$PROJECT_ROOT/.env.s3"
cat > "$ENV_FILE" <<EOF
# S3 Configuration (from Terraform)
# Source this file: source .env.s3

export ICEBERG_WAREHOUSE="s3://${BUCKET}/iceberg"
export BRONZE_CKPT="s3://${BUCKET}/checkpoints/bronze/raw_cdc"
export SILVER_CKPT="s3://${BUCKET}/checkpoints/silver/merge"
export S3_ENDPOINT="https://s3.${REGION}.amazonaws.com"
export S3_ACCESS_KEY="${ACCESS_KEY}"
export S3_SECRET_KEY="${SECRET_KEY}"
export S3_PATH_STYLE="false"
EOF

echo "✅ S3 configuration saved to: $ENV_FILE"
echo ""
echo "To use S3 configuration:"
echo "  source $ENV_FILE"
echo ""
echo "To switch back to MinIO:"
echo "  source $PROJECT_ROOT/.env.minio  # (if exists) or unset these variables"
