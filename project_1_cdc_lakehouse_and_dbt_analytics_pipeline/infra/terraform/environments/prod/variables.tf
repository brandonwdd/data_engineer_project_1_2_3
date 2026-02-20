# Variables for production environment

variable "project_name" {
  description = "Project name (used for resource naming)"
  type        = string
  default     = "project1"
}

variable "environment" {
  description = "Environment name (prod, stg, dev)"
  type        = string
  default     = "prod"
}

variable "aws_region" {
  description = "AWS region for resources"
  type        = string
  default     = "us-east-1"
}

variable "enable_versioning" {
  description = "Enable S3 bucket versioning"
  type        = bool
  default     = false  # Set to true for production data protection
}
