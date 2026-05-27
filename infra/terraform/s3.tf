# =============================================
# S3 — Deploy Staging Bucket
# =============================================
# GitHub Actions 가 docker-compose.prod.yml 을 업로드하고
# EC2 가 SSM Run Command 안에서 다운로드해 사용한다 (ADR-0008).
#
# - SSE-S3 (AES256) 암호화
# - Public 접근 전면 차단
# - HTTPS-only bucket policy (aws:SecureTransport)
# - 7 일 후 객체 자동 삭제 (배포 산출물만 보관)
#
# Access logging 미적용 사유 (SonarQube hotspot Acknowledged):
#   - 단일 writer(GitHub Actions OIDC role) + 단일 reader(EC2 IAM role) 구조라 audit 가치 낮음
#   - 별도 log bucket 운영비/복잡도 대비 효용 부족 (1인 MVP)
#   - 감사 필요 시 CloudTrail S3 Data Events 로 충분 (Free Tier 100,000 events/m)
#   - 산출물 자체도 docker-compose.yml(평문, 비밀 없음) 1개라 민감도 낮음

resource "aws_s3_bucket" "deploy_staging" { # NOSONAR: access logging 미적용 사유는 파일 헤더 참조
  bucket = "kicklog-deploy-staging-${data.aws_caller_identity.current.account_id}"

  # AWS S3 tag value 는 ASCII letters/numbers/spaces + +-=._:/@ 만 허용.
  # 한글/화살표/괄호 사용 불가 — 상세 설명은 본 파일 헤더 + ADR-0008 참조.
  tags = {
    Name    = "kicklog-deploy-staging"
    Purpose = "cd-via-ssm-adr-0008"
  }
}

# HTTPS-only bucket policy (SonarQube hotspot — 정공법 반영).
# aws:SecureTransport = false 인 요청을 전면 거부.
resource "aws_s3_bucket_policy" "deploy_staging_https_only" {
  bucket = aws_s3_bucket.deploy_staging.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "DenyInsecureTransport"
      Effect    = "Deny"
      Principal = "*"
      Action    = "s3:*"
      Resource = [
        aws_s3_bucket.deploy_staging.arn,
        "${aws_s3_bucket.deploy_staging.arn}/*",
      ]
      Condition = {
        Bool = {
          "aws:SecureTransport" = "false"
        }
      }
    }]
  })

  # public_access_block 가 먼저 적용된 후 정책 적용 (race 방지)
  depends_on = [aws_s3_bucket_public_access_block.deploy_staging]
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
