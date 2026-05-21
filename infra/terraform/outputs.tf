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
