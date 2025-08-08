# modules/s3/main.tf

resource "random_string" "bucket_suffix" {
  length  = 8
  special = false
  upper   = false
}

# S3 Bucket for static assets and file storage
resource "aws_s3_bucket" "main" {
  bucket = "${var.project_name}-${var.environment}-bucket-${random_string.bucket_suffix.result}"

  tags = {
    Name = "${var.project_name}-${var.environment}-bucket"
  }
}

# S3 Bucket Versioning
resource "aws_s3_bucket_versioning" "main" {
  bucket = aws_s3_bucket.main.id
  versioning_configuration {
    status = "Enabled"
  }
}

# S3 Bucket Server Side Encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "main" {
  bucket = aws_s3_bucket.main.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# S3 Bucket Public Access Block
resource "aws_s3_bucket_public_access_block" "main" {
  bucket = aws_s3_bucket.main.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Upload sample static assets
resource "aws_s3_object" "sample_static" {
  bucket = aws_s3_bucket.main.id
  key    = "static/sample.txt"
  content = "This is a sample static file for the File Server application."
  
  tags = {
    Name = "sample-static-file"
  }
}