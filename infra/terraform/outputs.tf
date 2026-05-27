# =============================================
# Outputs — terraform apply 후 출력
# =============================================

output "ec2_public_ip" {
  description = "EC2 Elastic IP (HTTP/SSH 접속용)"
  value       = aws_eip.app.public_ip
}

output "ssh_command" {
  description = "SSH 접속 명령"
  value       = "ssh -i ~/.ssh/${var.ssh_key_name}.pem ec2-user@${aws_eip.app.public_ip}"
}

output "rds_endpoint" {
  description = "RDS PostgreSQL endpoint (EC2에서만 접근)"
  value       = aws_db_instance.main.endpoint
}

output "rds_database_name" {
  description = "초기 데이터베이스 이름"
  value       = aws_db_instance.main.db_name
}

output "secrets_db_password_arn" {
  description = "Secrets Manager ARN — DB 비밀번호"
  value       = aws_secretsmanager_secret.db_password.arn
}

output "secrets_kakao_arn" {
  description = "Secrets Manager ARN — Kakao API 키"
  value       = aws_secretsmanager_secret.kakao_rest_api_key.arn
}

output "secrets_jwt_arn" {
  description = "Secrets Manager ARN — JWT secret"
  value       = aws_secretsmanager_secret.jwt_secret.arn
}

output "aws_account_id" {
  description = "현재 AWS 계정 ID"
  value       = data.aws_caller_identity.current.account_id
  sensitive   = true
}

# ─── CD (ADR-0008) — GitHub repository Variables 에 입력 ──
output "github_actions_role_arn" {
  description = "GitHub Actions OIDC AssumeRole 대상 ARN (Variable: AWS_GITHUB_ROLE_ARN)"
  value       = aws_iam_role.github_actions_ci.arn
}

output "deploy_staging_bucket_name" {
  description = "배포 산출물 스테이징 버킷 이름 (Variable: DEPLOY_STAGING_BUCKET)"
  value       = aws_s3_bucket.deploy_staging.bucket
}

output "ec2_instance_id" {
  description = "SSM 타겟 EC2 instance ID (Variable: EC2_INSTANCE_ID)"
  value       = aws_instance.app.id
}

output "secrets_ghcr_pat_arn" {
  description = "Secrets Manager ARN — GHCR PAT"
  value       = aws_secretsmanager_secret.ghcr_pat.arn
}

# ─── Observability / Budget (ADR-0009) ───────────────
output "sns_alerts_topic_arn" {
  description = "운영 알림 SNS Topic ARN — 추가 구독자(slack 등)는 본 ARN 에 subscribe"
  value       = aws_sns_topic.alerts.arn
}

output "budget_name" {
  description = "AWS Budgets 월 한도 이름 (Console > Billing > Budgets 에서 조회)"
  value       = aws_budgets_budget.monthly.name
}

output "ssh_inbound_enabled" {
  description = "SSH(22) ingress 활성화 여부 (false 이면 SSM Session Manager 만 사용)"
  value       = var.enable_ssh_inbound
}
