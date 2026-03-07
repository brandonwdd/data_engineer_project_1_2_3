# Terraform IaC Explained

## What is Terraform?

**Terraform** is an Infrastructure as Code (IaC) tool by HashiCorp.

### Simple Explanation

**Traditional way** (manual):
```
1. Log into AWS console
2. Click "Create S3 bucket"
3. Fill bucket name, region
4. Click "Create"
5. Create IAM user
6. Configure permissions
7. ...
```

**Terraform way** (code-defined):
```hcl
resource "aws_s3_bucket" "warehouse" {
  bucket = "project1-warehouse"
  region = "us-east-1"
}

resource "aws_iam_user" "s3_user" {
  name = "project1-s3-access"
}
```

Then run `terraform apply` to create all resources automatically.

---

##  Core Concepts

### 1. Infrastructure as Code (IaC)

**Definition**: Define and manage infrastructure (servers, databases, storage, networks) as code

**Benefits**:
-  **Version control**: Infrastructure config managed in Git
-  **Repeatable**: Same code creates identical infrastructure in dev/stg/prod
-  **Auditable**: All changes recorded (Git commit history)
-  **Automated**: No manual clicks, `terraform apply` one-command deploy
-  **Consistent**: Avoids "manual config causes environment drift"

### 2. Terraform Workflow

```
1. Write .tf files (define resources needed)
   ↓
2. terraform init (initialize, download provider plugins)
   ↓
3. terraform plan (preview: what will be created/modified/deleted)
   ↓
4. terraform apply (execute: actually create resources)
   ↓
5. terraform destroy (cleanup: delete all resources)
```

---

##  Role in Project 1

### Current State

**Local dev**: Docker Compose + MinIO (local S3-compatible storage)
-  No AWS account needed
-  Zero cost
-  Sufficient for production-style demo

**Production**: Needs real AWS S3 (or other cloud storage)
-  AWS account required
-  Access credentials needed
-  Will incur costs (though S3 is cheap)

### What Terraform Should Do

#### 1. **Create S3 Bucket** (object storage)

```hcl
# infra/terraform/environments/prod/main.tf

resource "aws_s3_bucket" "warehouse" {
  bucket = "project1-warehouse-prod"
  
  tags = {
    Environment = "production"
    Project     = "project1"
  }
}

# Enable versioning (optional, for data protection)
resource "aws_s3_bucket_versioning" "warehouse" {
  bucket = aws_s3_bucket.warehouse.id
  versioning_configuration {
    status = "Enabled"
  }
}
```

**Purpose**: Replace local MinIO with real AWS S3 for Iceberg data

---

#### 2. **Create IAM User/Role** (access permissions)

```hcl
# Create IAM user (Spark jobs access S3)
resource "aws_iam_user" "spark_s3_access" {
  name = "project1-spark-s3-user"
}

# Create access key
resource "aws_iam_access_key" "spark_s3" {
  user = aws_iam_user.spark_s3_access.name
}

# Create policy (allow read/write S3 bucket)
resource "aws_iam_user_policy" "spark_s3_policy" {
  user = aws_iam_user.spark_s3_access.name
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ]
        Resource = [
          "${aws_s3_bucket.warehouse.arn}/*",
          aws_s3_bucket.warehouse.arn
        ]
      }
    ]
  })
}
```

**Purpose**: Provide secure S3 access credentials for Spark jobs (not hardcoded keys)

---

#### 3. **Create EKS Cluster** (optional, K8s in cloud)

```hcl
# If running K8s on AWS (instead of local kind/k3d)
resource "aws_eks_cluster" "project1" {
  name     = "project1-eks"
  role_arn = aws_iam_role.eks_cluster.arn
  
  vpc_config {
    subnet_ids = [aws_subnet.public[0].id, aws_subnet.public[1].id]
  }
}
```

**Purpose**: Run Kubernetes on AWS (but requirements say "no need to run EKS permanently", so optional)

---

#### 4. **Environment Variable Switching** (MinIO vs S3)

```hcl
# variables.tf
variable "storage_backend" {
  description = "Storage backend: minio (local) or s3 (AWS)"
  type        = string
  default     = "minio"
}

variable "s3_bucket_name" {
  description = "S3 bucket name (if storage_backend = s3)"
  type        = string
  default     = ""
}

# main.tf
locals {
  # Choose config based on storage_backend
  warehouse_path = var.storage_backend == "s3" 
    ? "s3://${var.s3_bucket_name}/iceberg"
    : "s3a://warehouse/iceberg"  # MinIO
  
  s3_endpoint = var.storage_backend == "s3"
    ? "https://s3.amazonaws.com"
    : "http://minio:9000"  # MinIO
}
```

**Purpose**: Same code can switch between local (MinIO) and production (S3)

---

##  Terraform Structure in Project

```
infra/terraform/
├── README.md                    # Terraform docs
├── environments/
│   ├── local/                   # Local env (MinIO)
│   │   ├── main.tf             # Main config (placeholder)
│   │   ├── variables.tf        # Variable definitions
│   │   ├── outputs.tf          # Outputs
│   │   └── terraform.tfvars.example  # Variable example
│   │
│   ├── dev/                     # Dev env (optional AWS)
│   │   └── ... (similar structure)
│   │
│   └── prod/                    # Prod env (AWS S3)
│       ├── main.tf             # S3 bucket + IAM
│       ├── variables.tf
│       └── outputs.tf          # Output S3 bucket name, IAM keys
```

---

##  Why "Optional"?

### Requirements Quote

> "Cost and real-world deployment (production-style but not expensive)
> - Runtime: local kind/k3d sufficient for production-style demo; **cloud only keeps Terraform code and optional verification**
> - Object storage: dev uses MinIO; **Terraform supports switching to S3**"

### Analysis

1. **Cost**
   - Local MinIO: free
   - AWS S3: cheap but requires AWS account, may incur costs
   - EKS: more expensive, requirements explicitly say "no need to run EKS permanently"

2. **Demo sufficient**
   - Local MinIO already demonstrates S3-compatible storage
   - K8s with local kind/k3d already demonstrates production style
   - **Terraform code itself** proves IaC capability (even without running)

3. **Interview value**
   - Having Terraform code = proves IaC skills
   - Not necessarily need to run on AWS (costly)

---

##  If Implementing, What to Do?

### Minimal Implementation (Recommended)

**Only implement S3 + IAM** (not EKS):

```hcl
# infra/terraform/environments/prod/main.tf

terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# S3 Bucket (Iceberg warehouse)
resource "aws_s3_bucket" "warehouse" {
  bucket = "${var.project_name}-warehouse-${var.environment}"
  
  tags = {
    Project     = var.project_name
    Environment = var.environment
  }
}

# IAM user (Spark access S3)
resource "aws_iam_user" "spark_s3" {
  name = "${var.project_name}-spark-s3-${var.environment}"
}

resource "aws_iam_access_key" "spark_s3" {
  user = aws_iam_user.spark_s3.name
}

resource "aws_iam_user_policy" "spark_s3_policy" {
  user = aws_iam_user.spark_s3.name
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ]
        Resource = [
          "${aws_s3_bucket.warehouse.arn}/*",
          aws_s3_bucket.warehouse.arn
        ]
      }
    ]
  })
}

# Outputs (for configuring Spark jobs)
output "s3_bucket_name" {
  value = aws_s3_bucket.warehouse.id
}

output "s3_access_key_id" {
  value     = aws_iam_access_key.spark_s3.id
  sensitive = true
}

output "s3_secret_access_key" {
  value     = aws_iam_access_key.spark_s3.secret
  sensitive = true
}
```

### Usage

```bash
# 1. Configure AWS credentials
export AWS_ACCESS_KEY_ID=your_key
export AWS_SECRET_ACCESS_KEY=your_secret

# 2. Initialize
cd infra/terraform/environments/prod
terraform init

# 3. Preview (what will be created)
terraform plan

# 4. Apply (actually create)
terraform apply

# 5. View outputs (S3 bucket name, IAM keys)
terraform output

# 6. Cleanup (delete all resources)
terraform destroy
```

---

## Interview Value

### Benefits of Having Terraform Code

1. **Proves IaC capability**
   - Interviewer: "Do you know IaC?"
   - You: "Yes, my project has Terraform code managing AWS resources"

2. **Shows production mindset**
   - Not manually creating resources
   - Code-based, versioned, repeatable

3. **Cost awareness**
   - Local uses MinIO (free)
   - Production uses S3 (managed by Terraform)
   - Shows cost consideration

### Even Without Running

-  Having Terraform code = proves you can write it
-  Can state in README: "Terraform code ready, supports one-command deploy to AWS"
-  Can show code in interview, explain design

---

##  Summary

**Terraform IaC** = Define and manage cloud resources (S3, IAM, EKS, etc.) as code

**In Project 1**:
- Purpose: Manage AWS S3 bucket and IAM permissions (replace local MinIO)
- Status:  Implemented
- Priority: High (IaC is production-grade requirement)

**Whether to implement**:
-  To demonstrate IaC: recommend implementing (at least S3 + IAM)
-  Implemented: S3 bucket + IAM user/policy

**Minimal implementation**: S3 bucket + IAM user/policy (~50-100 lines of Terraform code)
