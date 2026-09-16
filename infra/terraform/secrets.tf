# =============================================
# Secrets Manager — 민감 정보 저장
# =============================================
# ADR-0006 D6: DB 비밀번호·카카오 키·JWT secret을 Secrets Manager에
# EC2는 IAM role로 접근 (ec2.tf 참조)

# ─── DB Password ──────────────────────────────────────
resource "aws_secretsmanager_secret" "db_password" {
  name                    = "kicklog/db-password"
  description             = "RDS PostgreSQL master password"
  recovery_window_in_days = 7 # 삭제 시 7일 복구 가능

  tags = {
    Name = "kicklog-db-password"
  }
}

resource "aws_secretsmanager_secret_version" "db_password" {
  secret_id = aws_secretsmanager_secret.db_password.id
  secret_string = jsonencode({
    username = var.rds_username
    password = var.rds_password
    host     = aws_db_instance.main.address
    port     = aws_db_instance.main.port
    dbname   = var.rds_db_name
  })
}

# ─── Kakao REST API Key ───────────────────────────────
resource "aws_secretsmanager_secret" "kakao_rest_api_key" {
  name                    = "kicklog/kakao-rest-api-key"
  description             = "Kakao Local API REST key (백엔드 프록시용)"
  recovery_window_in_days = 7

  tags = {
    Name = "kicklog-kakao-rest-api-key"
  }
}

resource "aws_secretsmanager_secret_version" "kakao_rest_api_key" {
  secret_id     = aws_secretsmanager_secret.kakao_rest_api_key.id
  secret_string = var.kakao_rest_api_key
}

# ─── JWT Signing Secret ───────────────────────────────
resource "aws_secretsmanager_secret" "jwt_secret" {
  name                    = "kicklog/jwt-secret"
  description             = "JWT 서명용 시크릿 (HS256, 32자 이상)"
  recovery_window_in_days = 7

  tags = {
    Name = "kicklog-jwt-secret"
  }
}

resource "aws_secretsmanager_secret_version" "jwt_secret" {
  secret_id     = aws_secretsmanager_secret.jwt_secret.id
  secret_string = var.jwt_secret
}

# ─── GHCR Personal Access Token ───────────────────────
# ADR-0008: GitHub Actions 가 SSM Run Command 로 docker login 시 사용.
# EC2 가 IAM role 로 fetch (cd.yml 의 SSM script 안에서 호출).
resource "aws_secretsmanager_secret" "ghcr_pat" {
  name                    = "kicklog/ghcr-pat"
  description             = "GHCR private package pull 용 PAT (docker login 시 사용)"
  recovery_window_in_days = 7

  tags = {
    Name = "kicklog-ghcr-pat"
  }
}

resource "aws_secretsmanager_secret_version" "ghcr_pat" {
  secret_id     = aws_secretsmanager_secret.ghcr_pat.id
  secret_string = var.ghcr_pat
}

# ─── Sentry DSN (에러 트래킹) ─────────────────────────
# 미발급(빈 값)이면 secret 자체를 만들지 않는다 — fetch-secrets.sh 가 빈 값으로 처리, 앱은 Sentry 비활성.
# DSN 발급 후 tfvars 에 채우고 apply 하면 secret 생성 → fetch-secrets.sh 재실행으로 주입.
resource "aws_secretsmanager_secret" "sentry_dsn" {
  count                   = var.sentry_dsn != "" ? 1 : 0
  name                    = "kicklog/sentry-dsn"
  description             = "Sentry DSN (백엔드 에러 트래킹)"
  recovery_window_in_days = 7

  tags = {
    Name = "kicklog-sentry-dsn"
  }
}

resource "aws_secretsmanager_secret_version" "sentry_dsn" {
  count         = var.sentry_dsn != "" ? 1 : 0
  secret_id     = aws_secretsmanager_secret.sentry_dsn[0].id
  secret_string = var.sentry_dsn
}

# tfvars 를 쓰지 않고 콘솔·CLI 로 직접 만든 sentry-dsn 을 참조한다 (ARN 만 쓰고 값은 읽지 않는다).
# EC2 IAM 정책(ec2.tf)이 이 ARN 에 GetSecretValue 를 허용해야 fetch-secrets.sh 가 주입할 수 있다.
# var.sentry_dsn 으로 terraform 이 직접 만든 경우에는 위 resource 가 잡으므로 이 data 는 count=0.
data "aws_secretsmanager_secret" "sentry_dsn_existing" {
  count = var.sentry_dsn == "" ? 1 : 0
  name  = "kicklog/sentry-dsn"
}
