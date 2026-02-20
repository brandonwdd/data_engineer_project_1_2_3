# Outputs for production environment

output "s3_bucket_name" {
  description = "S3 bucket name for Iceberg warehouse"
  value       = aws_s3_bucket.warehouse.id
}

output "s3_bucket_arn" {
  description = "S3 bucket ARN"
  value       = aws_s3_bucket.warehouse.arn
}

output "s3_access_key_id" {
  description = "IAM access key ID for Spark S3 access"
  value       = aws_iam_access_key.spark_s3.id
  sensitive   = true
}

output "s3_secret_access_key" {
  description = "IAM secret access key for Spark S3 access"
  value       = aws_iam_access_key.spark_s3.secret
  sensitive   = true
}

output "iceberg_warehouse_path" {
  description = "Iceberg warehouse path (s3://bucket/iceberg)"
  value       = "s3://${aws_s3_bucket.warehouse.id}/iceberg"
}

output "checkpoint_location" {
  description = "Spark checkpoint location (s3://bucket/checkpoints)"
  value       = "s3://${aws_s3_bucket.warehouse.id}/checkpoints"
}
