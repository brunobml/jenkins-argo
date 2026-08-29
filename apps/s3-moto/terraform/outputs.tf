output "bucket_name" {
  description = "Name of the S3 bucket."
  value       = aws_s3_bucket.app.bucket
}

output "bucket_arn" {
  description = "ARN of the S3 bucket."
  value       = aws_s3_bucket.app.arn
}

output "object_key" {
  description = "Key of the object uploaded to the bucket."
  value       = aws_s3_object.readme.key
}
