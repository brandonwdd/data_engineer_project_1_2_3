# Outputs for dev environment

output "storage_backend" {
  description = "Storage backend: 's3' or 'minio'"
  value       = var.use_aws_s3 ? "s3" : "minio"
}

output "s3_bucket_name" {
  description = "S3 bucket name (if use_aws_s3 = true)"
  value       = var.use_aws_s3 ? aws_s3_bucket.warehouse[0].id : null
}

output "s3_access_key_id" {
  description = "IAM access key ID (if use_aws_s3 = true)"
  value       = var.use_aws_s3 ? aws_iam_access_key.spark_s3[0].id : null
  sensitive   = true
}

output "s3_secret_access_key" {
  description = "IAM secret access key (if use_aws_s3 = true)"
  value       = var.use_aws_s3 ? aws_iam_access_key.spark_s3[0].secret : null
  sensitive   = true
}

output "iceberg_warehouse_path" {
  description = "Iceberg warehouse path"
  value = var.use_aws_s3 
    ? "s3://${aws_s3_bucket.warehouse[0].id}/iceberg"
    : "s3a://warehouse/iceberg"  # MinIO
}

output "s3_endpoint" {
  description = "S3 endpoint URL"
  value = var.use_aws_s3
    ? "https://s3.${var.aws_region}.amazonaws.com"
    : "http://minio:9000"  # MinIO
}
