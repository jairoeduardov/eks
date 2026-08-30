# Buckets S3 de invoicing-service: imagenes de items y certificados DTE del
# firmador interno (perfil firmador-interno, ver S3CertificateProvider.java).

resource "aws_s3_bucket" "invoicing_uploads" {
  bucket = "${local.name}-invoicing-uploads-${data.aws_caller_identity.current.account_id}"
  tags   = local.tags
}

resource "aws_s3_bucket_public_access_block" "invoicing_uploads" {
  bucket                  = aws_s3_bucket.invoicing_uploads.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket" "invoicing_certs" {
  bucket = "${local.name}-invoicing-certs-${data.aws_caller_identity.current.account_id}"
  tags   = local.tags
}

resource "aws_s3_bucket_public_access_block" "invoicing_certs" {
  bucket                  = aws_s3_bucket.invoicing_certs.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Certificados DTE cifrados en reposo: son material sensible (firma legal de
# comprobantes tributarios).
resource "aws_s3_bucket_server_side_encryption_configuration" "invoicing_certs" {
  bucket = aws_s3_bucket.invoicing_certs.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

output "invoicing_uploads_bucket" {
  value = aws_s3_bucket.invoicing_uploads.bucket
}

output "invoicing_certs_bucket" {
  value = aws_s3_bucket.invoicing_certs.bucket
}
