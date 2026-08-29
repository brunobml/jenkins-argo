variable "bucket_name" {
  description = "Name of the S3 bucket the s3-consumer app uses."
  type        = string
  default     = "s3-consumer-demo"
}

# For real AWS: leave s3_endpoint empty ("") so the provider talks to AWS
# directly. For Moto on the k3d host, host.k3d.internal reaches localhost:5000.
variable "s3_endpoint" {
  description = "Override URL for the S3 API. Empty means real AWS."
  type        = string
  default     = "http://host.k3d.internal:5000"
}

variable "aws_region" {
  description = "AWS region. us-east-1 keeps bucket creation idempotent under Moto."
  type        = string
  default     = "us-east-1"
}
