# =============================================
# S3 — Deploy Staging Bucket
# =============================================
# GitHub Actions 가 docker-compose.prod.yml 을 업로드하고
# EC2 가 SSM Run Command 안에서 다운로드해 사용한다 (ADR-0008).
#
# - SSE-S3 (AES256) 암호화
# - Public 접근 전면 차단
# - 7 일 후 객체 자동 삭제 (배포 산출물만 보관)

resource "aws_s3_bucket" "deploy_staging" {
  bucket = "kicklog-deploy-staging-${data.aws_caller_identity.current.account_id}"

  tags = {
    Name    = "kicklog-deploy-staging"
    Purpose = "GitHub Actions → EC2 배포 산출물 스테이징 (ADR-0008)"
  }
}

resource "aws_s3_bucket_public_access_block" "deploy_staging" {
  bucket = aws_s3_bucket.deploy_staging.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "deploy_staging" {
  bucket = aws_s3_bucket.deploy_staging.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "deploy_staging" {
  bucket = aws_s3_bucket.deploy_staging.id

  rule {
    id     = "expire-deploy-artifacts"
    status = "Enabled"

    filter {} # 전체 객체 대상

    expiration {
      days = 7
    }
  }
}
