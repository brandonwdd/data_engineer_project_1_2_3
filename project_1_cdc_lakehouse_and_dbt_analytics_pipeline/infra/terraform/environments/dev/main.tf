# Terraform configuration for Project 1 - Dev environment (optional AWS, or local MinIO)

terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# Only create AWS resources if use_aws_s3 is true
# If false, use local MinIO (no AWS resources needed)
variable "use_aws_s3" {
  description = "Use AWS S3 (true) or local MinIO (false)"
  type        = bool
  default     = false
}

provider "aws" {
  region = var.use_aws_s3 ? var.aws_region : null
}

# S3 Bucket (only if use_aws_s3 = true)
resource "aws_s3_bucket" "warehouse" {
  count  = var.use_aws_s3 ? 1 : 0
  bucket = "${var.project_name}-warehouse-${var.environment}"
}

# IAM User (only if use_aws_s3 = true)
resource "aws_iam_user" "spark_s3" {
  count = var.use_aws_s3 ? 1 : 0
  name  = "${var.project_name}-spark-s3-${var.environment}"
}

resource "aws_iam_access_key" "spark_s3" {
  count = var.use_aws_s3 ? 1 : 0
  user  = aws_iam_user.spark_s3[0].name
}

resource "aws_iam_user_policy" "spark_s3_policy" {
  count = var.use_aws_s3 ? 1 : 0
  name  = "${var.project_name}-spark-s3-policy-${var.environment}"
  user  = aws_iam_user.spark_s3[0].name

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
          "${aws_s3_bucket.warehouse[0].arn}/*",
          aws_s3_bucket.warehouse[0].arn
        ]
      }
    ]
  })
}
