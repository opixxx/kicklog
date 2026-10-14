# =============================================
# SSM Parameter Store — 민감 정보 저장
# =============================================
# ADR-0016: Secrets Manager($0.40/secret/월 × 5 = $2.0/월) → SSM Parameter Store.
#
# 비용 외에 일원화 목적도 있다 — ADR-0015 가 Origin CA 인증서와 Cloudflare 토큰을
# SSM 에 두면서 비밀 저장소가 2개로 갈라져 있었다. 이제 전부 /kicklog/* 아래 모인다.
#
# Standard tier + AWS 관리형 키(alias/aws/ssm) → 저장·조회 모두 무료.
# 포기하는 것: 자동 rotation(미사용), 교차계정 공유(미사용).
#
# terraform 이 직접 만들지 않는 파라미터 (스크립트가 생성, ADR-0015):
#   /kicklog/origin-cert · /kicklog/origin-key · /kicklog/cloudflare-api-token
# EC2 IAM 은 /kicklog/* 전체에 GetParameter 를 허용하므로 둘 다 커버된다.

resource "aws_ssm_parameter" "db_password" {
  name        = "/kicklog/db-password"
  description = "Postgres 컨테이너 master password (ADR-0016 이후 컨테이너 내부 DB)"
  type        = "SecureString"
  value       = var.db_password

  tags = {
    Name = "kicklog-db-password"
  }
}

resource "aws_ssm_parameter" "kakao_rest_api_key" {
  name        = "/kicklog/kakao-rest-api-key"
  description = "Kakao Local API REST key (백엔드 프록시용)"
  type        = "SecureString"
  value       = var.kakao_rest_api_key

  tags = {
    Name = "kicklog-kakao-rest-api-key"
  }
}

resource "aws_ssm_parameter" "jwt_secret" {
  name        = "/kicklog/jwt-secret"
  description = "JWT 서명용 시크릿 (HS256, 32자 이상)"
  type        = "SecureString"
  value       = var.jwt_secret

  tags = {
    Name = "kicklog-jwt-secret"
  }
}

resource "aws_ssm_parameter" "ghcr_pat" {
  name        = "/kicklog/ghcr-pat"
  description = "GHCR private package pull 용 PAT (docker login, ADR-0008)"
  type        = "SecureString"
  value       = var.ghcr_pat

  tags = {
    Name = "kicklog-ghcr-pat"
  }
}

# Sentry DSN — 빈 값이면 파라미터를 만들지 않는다.
# fetch-secrets.sh 는 "없음(정상)" 과 "있는데 못 읽음(권한 오류)" 을 구분해 처리한다.
resource "aws_ssm_parameter" "sentry_dsn" {
  count       = var.sentry_dsn != "" ? 1 : 0
  name        = "/kicklog/sentry-dsn"
  description = "Sentry DSN (백엔드 에러 트래킹)"
  type        = "SecureString"
  value       = var.sentry_dsn

  tags = {
    Name = "kicklog-sentry-dsn"
  }
}
