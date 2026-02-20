# Variables for dev environment

variable "project_name" {
  description = "Project name"
  type        = string
  default     = "project1"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "dev"
}

variable "aws_region" {
  description = "AWS region (only used if use_aws_s3 = true)"
  type        = string
  default     = "us-east-1"
}

variable "use_aws_s3" {
  description = "Use AWS S3 (true) or local MinIO (false)"
  type        = bool
  default     = false
}
