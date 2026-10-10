# =============================================
# Backup — 논리 백업(pg_dump) 보관 버킷
# =============================================
# ADR-0015: RDS 자동 스냅샷(7일)과 별도로 pg_dump 논리 백업을 S3 에 둔다.
#
# 자동 스냅샷만으로 부족한 이유:
#   - 스냅샷은 계정·리전·KMS 키에 묶인다 (AWS 관리형 키로 암호화돼 교차 계정 공유 불가)
#   - 테이블 1개만 되살리는 부분 복구가 불가능하다
#   - 엔진 버전 업그레이드 사고 시 되돌릴 포맷이 없다
# pg_dump -Fc 는 이 세 경우를 모두 커버하고, 다운로드해서 로컬 psql 로 열 수 있다.
#
# 비용: DB 실사용 약 2.9GB → 압축 덤프는 수십 MB 수준. 30일 보관해도 월 $0.1 미만.
# s3.tf 의 deploy_staging 버킷과 같은 보안 기준을 적용한다
# (public 4축 차단 · SSE-S3 · HTTPS-only · lifecycle).

resource "aws_s3_bucket" "backup" { # NOSONAR: access logging 미적용 사유는 s3.tf 헤더와 동일
  bucket = "kicklog-backup-${data.aws_caller_identity.current.account_id}"

  tags = {
    Name    = "kicklog-backup"
    Purpose = "pg-dump-logical-backup-adr-0015"
  }
}

resource "aws_s3_bucket_public_access_block" "backup" {
  bucket = aws_s3_bucket.backup.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "backup" {
  bucket = aws_s3_bucket.backup.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# 백업은 버전 관리 대상이 아니다 (객체 키에 타임스탬프가 들어가 매번 새 객체).
# 평문 전송 차단만 정책으로 강제한다.
resource "aws_s3_bucket_policy" "backup_https_only" {
  bucket = aws_s3_bucket.backup.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "DenyInsecureTransport"
      Effect    = "Deny"
      Principal = "*"
      Action    = "s3:*"
      Resource = [
        aws_s3_bucket.backup.arn,
        "${aws_s3_bucket.backup.arn}/*",
      ]
      Condition = {
        Bool = {
          "aws:SecureTransport" = "false"
        }
      }
    }]
  })

  depends_on = [aws_s3_bucket_public_access_block.backup]
}

resource "aws_s3_bucket_lifecycle_configuration" "backup" {
  bucket = aws_s3_bucket.backup.id

  rule {
    id     = "expire-pg-dumps"
    status = "Enabled"

    filter {
      prefix = "pg/"
    }

    # 30일 보관 — RDS 자동 스냅샷(7일)보다 길게 둬서 "늦게 알아차린 사고" 를 커버한다.
    expiration {
      days = 30
    }

    # 중단된 멀티파트 업로드가 과금되지 않도록 정리 (덤프가 커지면 멀티파트가 된다)
    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

output "backup_bucket_name" {
  description = "pg_dump 논리 백업 버킷 이름"
  value       = aws_s3_bucket.backup.bucket
}
