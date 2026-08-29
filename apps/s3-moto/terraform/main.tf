# Same config for Moto and for real AWS. The only switch is var.s3_endpoint:
#   - set   -> talk to Moto (dummy creds, path-style, skip the AWS-only checks)
#   - empty -> talk to real AWS (ambient credential chain, normal endpoints)
provider "aws" {
  region = var.aws_region

  access_key = var.s3_endpoint == "" ? null : "test"
  secret_key = var.s3_endpoint == "" ? null : "test"

  skip_credentials_validation = var.s3_endpoint != ""
  skip_metadata_api_check     = var.s3_endpoint != ""
  skip_region_validation      = var.s3_endpoint != ""
  skip_requesting_account_id  = var.s3_endpoint != ""
  s3_use_path_style           = var.s3_endpoint != ""

  dynamic "endpoints" {
    for_each = var.s3_endpoint == "" ? [] : [var.s3_endpoint]
    content {
      s3 = endpoints.value
    }
  }
}

resource "aws_s3_bucket" "app" {
  bucket = var.bucket_name

  # The s3-consumer app writes objects Terraform does not track, so let
  # `terraform destroy` empty the bucket before removing it.
  force_destroy = true

  tags = {
    Environment = "local"
    ManagedBy   = "terraform"
    DeployedVia = "argo-workflows"
  }
}

resource "aws_s3_object" "readme" {
  bucket       = aws_s3_bucket.app.id
  key          = "README.txt"
  content      = "Bucket provisioned by the s3-moto-terraform Argo Workflow.\n"
  content_type = "text/plain"
}
