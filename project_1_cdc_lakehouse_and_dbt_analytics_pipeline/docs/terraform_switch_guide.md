# Terraform Output → Spark Config Switch Guide

## Switch from MinIO to AWS S3

### 1. Run Terraform to create S3 bucket + IAM

```bash
cd infra/terraform/environments/prod

# Configure AWS credentials
export AWS_ACCESS_KEY_ID=your_key
export AWS_SECRET_ACCESS_KEY=your_secret

# Initialize and apply
terraform init
terraform apply

# View outputs
terraform output
```

### 2. Get Terraform output values

```bash
# Get S3 bucket name
BUCKET=$(terraform output -raw s3_bucket_name)

# Get IAM access keys
ACCESS_KEY=$(terraform output -raw s3_access_key_id)
SECRET_KEY=$(terraform output -raw s3_secret_access_key)

# Get AWS region (from terraform.tfvars)
REGION=$(grep aws_region terraform.tfvars | cut -d'"' -f2)
```

### 3. Configure Spark job environment variables

#### Method 1: Docker Compose (Recommended)

Add to `spark` service in `platform/local/docker-compose.yml`:

```yaml
spark:
  environment:
    # Switch from MinIO to S3
    ICEBERG_WAREHOUSE: "s3://${BUCKET}/iceberg"
    BRONZE_CKPT: "s3://${BUCKET}/checkpoints/bronze/raw_cdc"
    SILVER_CKPT: "s3://${BUCKET}/checkpoints/silver/merge"
    S3_ENDPOINT: "https://s3.${REGION}.amazonaws.com"
    S3_ACCESS_KEY: "${ACCESS_KEY}"
    S3_SECRET_KEY: "${SECRET_KEY}"
    S3_PATH_STYLE: "false"  # S3 doesn't need path-style
```

#### Method 2: Environment variables (direct run)

```bash
export ICEBERG_WAREHOUSE="s3://${BUCKET}/iceberg"
export BRONZE_CKPT="s3://${BUCKET}/checkpoints/bronze/raw_cdc"
export SILVER_CKPT="s3://${BUCKET}/checkpoints/silver/merge"
export S3_ENDPOINT="https://s3.${REGION}.amazonaws.com"
export S3_ACCESS_KEY="${ACCESS_KEY}"
export S3_SECRET_KEY="${SECRET_KEY}"
export S3_PATH_STYLE="false"
```

#### Method 3: K8s ConfigMap/Secret

```bash
# Create Secret (sensitive data)
kubectl create secret generic s3-credentials \
  --from-literal=access-key="${ACCESS_KEY}" \
  --from-literal=secret-key="${SECRET_KEY}" \
  -n project1-cdc-prod

# Create ConfigMap (non-sensitive config)
kubectl create configmap spark-config \
  --from-literal=iceberg-warehouse="s3://${BUCKET}/iceberg" \
  --from-literal=s3-endpoint="https://s3.${REGION}.amazonaws.com" \
  --from-literal=s3-path-style="false" \
  -n project1-cdc-prod
```

### 4. Switch back to MinIO

```bash
# Restore default config (MinIO)
export ICEBERG_WAREHOUSE="s3a://warehouse/iceberg"
export BRONZE_CKPT="s3a://warehouse/checkpoints/bronze/raw_cdc"
export S3_ENDPOINT="http://minio:9000"
export S3_ACCESS_KEY="minioadmin"
export S3_SECRET_KEY="minioadmin"
export S3_PATH_STYLE="true"
```

---

## Config Comparison

| Config | MinIO (local) | AWS S3 (prod) |
|--------|--------------|---------------|
| `ICEBERG_WAREHOUSE` | `s3a://warehouse/iceberg` | `s3://bucket-name/iceberg` |
| `S3_ENDPOINT` | `http://minio:9000` | `https://s3.region.amazonaws.com` |
| `S3_ACCESS_KEY` | `minioadmin` | IAM key from Terraform output |
| `S3_SECRET_KEY` | `minioadmin` | IAM secret from Terraform output |
| `S3_PATH_STYLE` | `true` | `false` |

---

## Verify Switch

### Check config

```bash
# Check env vars in Spark container
docker exec spark env | grep -E "S3_|ICEBERG_"
```

### Test connection

```bash
# Test S3 connection in Spark container
docker exec spark \
  spark-sql --master local[*] \
  --packages org.apache.iceberg:iceberg-spark-runtime-3.5_2.12:1.4.2 \
  -e "SHOW NAMESPACES IN iceberg;"
```

---

## Automation Script

Create `scripts/switch_to_s3.sh`:

```bash
#!/bin/bash
# Switch to S3 config from Terraform output

cd infra/terraform/environments/prod

BUCKET=$(terraform output -raw s3_bucket_name)
ACCESS_KEY=$(terraform output -raw s3_access_key_id)
SECRET_KEY=$(terraform output -raw s3_secret_access_key)
REGION=$(grep aws_region terraform.tfvars | cut -d'"' -f2)

cat > /tmp/s3_env.sh <<EOF
export ICEBERG_WAREHOUSE="s3://${BUCKET}/iceberg"
export BRONZE_CKPT="s3://${BUCKET}/checkpoints/bronze/raw_cdc"
export SILVER_CKPT="s3://${BUCKET}/checkpoints/silver/merge"
export S3_ENDPOINT="https://s3.${REGION}.amazonaws.com"
export S3_ACCESS_KEY="${ACCESS_KEY}"
export S3_SECRET_KEY="${SECRET_KEY}"
export S3_PATH_STYLE="false"
EOF

echo "S3 configuration saved to /tmp/s3_env.sh"
echo "Source it: source /tmp/s3_env.sh"
```

---

## Notes

1. **S3 bucket name must be globally unique** (shared across all AWS accounts)
2. **IAM keys are sensitive**; don't commit to Git
3. **Restart Spark jobs** after switching for changes to take effect
4. **MinIO and S3 data are separate**; ensure data migration before switching (if needed)
