# Terraform for Project 1

## Overview

Terraform manages AWS infrastructure (S3 bucket + IAM), supports switching between local MinIO and cloud S3.

## Environments

- **local**: Use MinIO (Docker Compose), no AWS needed
- **dev**: Optional AWS S3 or MinIO (via `use_aws_s3` variable)
- **prod**: Use AWS S3 (required)

## Quick Start

### Production (AWS S3)

```bash
cd infra/terraform/environments/prod

# 1. Configure AWS credentials
export AWS_ACCESS_KEY_ID=your_key
export AWS_SECRET_ACCESS_KEY=your_secret

# 2. Copy and edit variables
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars, set aws_region, etc.

# 3. Initialize
terraform init

# 4. Preview (what will be created)
terraform plan

# 5. Apply (create S3 bucket + IAM)
terraform apply

# 6. View outputs (S3 bucket name, IAM keys)
terraform output

# 7. Cleanup (delete all resources)
terraform destroy
```

### Development (MinIO or S3)

```bash
cd infra/terraform/environments/dev

# Use MinIO (default)
cp terraform.tfvars.example terraform.tfvars
# Set use_aws_s3 = false

# Or use AWS S3
# Set use_aws_s3 = true, configure AWS credentials

terraform init
terraform plan
terraform apply
terraform output
```

## Using Output Values

Terraform outputs can configure Spark jobs:

```bash
# Get S3 bucket name
BUCKET=$(terraform output -raw s3_bucket_name)

# Get IAM keys (sensitive)
ACCESS_KEY=$(terraform output -raw s3_access_key_id)
SECRET_KEY=$(terraform output -raw s3_secret_access_key)

# Configure Spark jobs
export ICEBERG_WAREHOUSE="s3://${BUCKET}/iceberg"
export S3_ACCESS_KEY="${ACCESS_KEY}"
export S3_SECRET_KEY="${SECRET_KEY}"
export S3_ENDPOINT="https://s3.amazonaws.com"
```

## Environment Switching

### Switch from MinIO to S3

1. Run Terraform to create S3 bucket + IAM
2. Get output values (bucket name, keys)
3. Update Spark config env vars:
   - `ICEBERG_WAREHOUSE=s3://bucket-name/iceberg`
   - `S3_ENDPOINT=https://s3.amazonaws.com`
   - `S3_ACCESS_KEY=...`
   - `S3_SECRET_KEY=...`

### Switch from S3 back to MinIO

1. Update Spark config env vars:
   - `ICEBERG_WAREHOUSE=s3a://warehouse/iceberg`
   - `S3_ENDPOINT=http://minio:9000`
   - `S3_ACCESS_KEY=minioadmin`
   - `S3_SECRET_KEY=minioadmin`

## Cost

- **MinIO (local)**: Free
- **AWS S3**: 
  - Storage: $0.023/GB/month
  - Requests: $0.0004/1000 PUT requests
  - For demo projects, typically < $1/month

## Security

- IAM user has minimal permissions (only access specified S3 bucket)
- S3 bucket blocks public access by default
- Access keys marked as sensitive (not shown in logs)

See `docs/terraform_explained.md` for details.
