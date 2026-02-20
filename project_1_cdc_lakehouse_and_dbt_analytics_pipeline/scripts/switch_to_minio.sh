#!/bin/bash
# switch_to_minio.sh: Switch back to MinIO config

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Generate MinIO environment file
ENV_FILE="$PROJECT_ROOT/.env.minio"
cat > "$ENV_FILE" <<EOF
# MinIO Configuration (local)
# Source this file: source .env.minio

export ICEBERG_WAREHOUSE="s3a://warehouse/iceberg"
export BRONZE_CKPT="s3a://warehouse/checkpoints/bronze/raw_cdc"
export SILVER_CKPT="s3a://warehouse/checkpoints/silver/merge"
export S3_ENDPOINT="http://minio:9000"
export S3_ACCESS_KEY="minioadmin"
export S3_SECRET_KEY="minioadmin"
export S3_PATH_STYLE="true"
EOF

echo "✅ MinIO configuration saved to: $ENV_FILE"
echo ""
echo "To use MinIO configuration:"
echo "  source $ENV_FILE"
