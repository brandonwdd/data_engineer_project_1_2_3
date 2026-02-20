# Terraform configuration for Project 1 - Production environment (AWS S3)

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
  
  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "Terraform"
    }
  }
}

# S3 Bucket for Iceberg warehouse
resource "aws_s3_bucket" "warehouse" {
  bucket = "${var.project_name}-warehouse-${var.environment}"

  # Prevent accidental deletion
  lifecycle {
    prevent_destroy = false  # Set to true in production if needed
  }
}

# Enable versioning (optional, for data protection)
resource "aws_s3_bucket_versioning" "warehouse" {
  bucket = aws_s3_bucket.warehouse.id
  
  versioning_configuration {
    status = var.enable_versioning ? "Enabled" : "Disabled"
  }
}

# Block public access (security best practice)
resource "aws_s3_bucket_public_access_block" "warehouse" {
  bucket = aws_s3_bucket.warehouse.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets  = true
}

# IAM User for Spark jobs to access S3
resource "aws_iam_user" "spark_s3" {
  name = "${var.project_name}-spark-s3-${var.environment}"
  
  tags = {
    Purpose = "Spark S3 access for Iceberg warehouse"
  }
}

# IAM Access Key for Spark user
resource "aws_iam_access_key" "spark_s3" {
  user = aws_iam_user.spark_s3.name
}

# IAM Policy: Allow Spark to read/write S3 bucket
resource "aws_iam_user_policy" "spark_s3_policy" {
  name = "${var.project_name}-spark-s3-policy-${var.environment}"
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
          "s3:ListBucket",
          "s3:GetBucketLocation"
        ]
        Resource = [
          "${aws_s3_bucket.warehouse.arn}/*",
          aws_s3_bucket.warehouse.arn
        ]
      }
    ]
  })
}
