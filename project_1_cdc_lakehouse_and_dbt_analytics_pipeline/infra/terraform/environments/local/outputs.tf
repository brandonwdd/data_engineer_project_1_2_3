# Local environment outputs (MinIO, no AWS resources)

output "storage_backend" {
  description = "Storage backend: always 'minio' for local"
  value       = "minio"
}

output "iceberg_warehouse_path" {
  description = "Iceberg warehouse path (MinIO)"
  value       = "s3a://warehouse/iceberg"
}

output "s3_endpoint" {
  description = "S3 endpoint URL (MinIO)"
  value       = "http://minio:9000"
}

output "s3_access_key" {
  description = "MinIO access key (default)"
  value       = "minioadmin"
}

output "s3_secret_key" {
  description = "MinIO secret key (default)"
  value       = "minioadmin"
  sensitive   = true
}
