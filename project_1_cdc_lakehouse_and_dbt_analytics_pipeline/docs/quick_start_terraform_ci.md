# Terraform + GitHub Actions Quick Start

## Terraform Usage (Create AWS S3)

### Prerequisites

1. **AWS account** (existing)
2. **AWS access credentials**:
   ```bash
   export AWS_ACCESS_KEY_ID=your_key
   export AWS_SECRET_ACCESS_KEY=your_secret
   ```
3. **Install Terraform**:
   ```bash
   # Windows (chocolatey)
   choco install terraform
   
   # Mac (homebrew)
   brew install terraform
   
   # Linux
   wget https://releases.hashicorp.com/terraform/1.5.0/terraform_1.5.0_linux_amd64.zip
   unzip terraform_1.5.0_linux_amd64.zip
   sudo mv terraform /usr/local/bin/
   ```

### Create S3 Bucket (Production)

```bash
cd infra/terraform/environments/prod

# 1. Copy and edit variables
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars, set aws_region (e.g., us-east-1)

# 2. Initialize (download AWS provider)
terraform init

# 3. Preview (what resources will be created)
terraform plan

# Output example:
# Plan: 4 to add, 0 to change, 0 to destroy.
#   + aws_s3_bucket.warehouse
#   + aws_iam_user.spark_s3
#   + aws_iam_access_key.spark_s3
#   + aws_iam_user_policy.spark_s3_policy

# 4. Apply (actually create resources)
terraform apply
# Enter yes to confirm

# 5. View outputs (S3 bucket name, IAM keys)
terraform output

# 6. Switch to S3 config
cd ../../..
make switch-to-s3
# Or manually: source .env.s3
```

### Switch Back to MinIO

```bash
make switch-to-minio
# Or manually: source .env.minio
```

### Cleanup (Delete S3 Bucket)

```bash
cd infra/terraform/environments/prod
terraform destroy
# Enter yes to confirm
```

---

## GitHub Actions CI/CD

### Auto Trigger

- **Pull Request** to main/master → CI runs automatically
- **Push** to main/master → CI runs automatically

### View CI Status

1. On GitHub repo page, click **"Actions"** tab
2. View latest workflow run
3. Click to view detailed logs for each job

### Run Locally (Simulate CI)

```bash
# Lint
black --check streaming/spark/
flake8 streaming/spark/ --max-line-length=120

# Tests
PYTHONPATH=. pytest streaming/spark/tests/ -v

# dbt
cd analytics/dbt
dbt deps
dbt compile
dbt test

# Terraform
terraform fmt -check -recursive infra/terraform/
cd infra/terraform/environments/prod
terraform init -backend=false
terraform validate
```

### Add CI Badge to README

Add to top of README.md:

```markdown
![CI](https://github.com/YOUR_USERNAME/YOUR_REPO/workflows/CI/badge.svg)
```

Replace `YOUR_USERNAME` and `YOUR_REPO` with your GitHub username and repo name.

---

## Environment Switch Examples

### Scenario 1: Local Dev (MinIO)

```bash
# Use default config (MinIO)
docker compose --profile bronze up -d
docker compose --profile bronze run --rm spark
```

### Scenario 2: Switch to AWS S3

```bash
# 1. Create S3 bucket (if not exists)
cd infra/terraform/environments/prod
terraform apply

# 2. Switch to S3 config
cd ../../..
make switch-to-s3
source .env.s3

# 3. Run Spark (using S3)
docker compose --profile bronze run --rm spark
```

### Scenario 3: Switch Back to MinIO

```bash
make switch-to-minio
source .env.minio
docker compose --profile bronze run --rm spark
```

---

## Notes

1. **S3 bucket name must be globally unique** (shared namespace across all AWS accounts)
   - If name taken, modify `project_name` in `terraform.tfvars`

2. **IAM keys are sensitive**
   - Don't commit `.env.s3` to Git (already in `.gitignore`)
   - Use K8s Secret or environment variables

3. **Cost**
   - S3 storage: ~$0.023/GB/month
   - For demo projects, typically < $1/month
   - Remember `terraform destroy` to clean up

4. **Restart Spark jobs** after switching for changes to take effect

---

## Next Steps

1.  Terraform implemented
2.  GitHub Actions CI/CD implemented
3.  **Run Terraform to create S3 bucket** (you have AWS account)
4.  **Run idempotency validation** (evidence #3)

Detailed docs:
- Terraform: `infra/terraform/README.md`
- Switch guide: `docs/terraform_switch_guide.md`
- CI/CD: `.github/README.md`
