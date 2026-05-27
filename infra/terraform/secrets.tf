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
