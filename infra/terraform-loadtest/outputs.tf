# =============================================
# Outputs
# =============================================

output "backend_public_ip" {
  description = "backend EC2 public IP — k6 target (http://<ip>:8080), 브라우저 확인용"
  value       = aws_instance.backend.public_ip
}

output "backend_private_ip" {
  description = "backend EC2 private IP — loadgen 에서 같은 VPC 로 타격(권장, 네트워크 변수 최소)"
  value       = aws_instance.backend.private_ip
}

output "loadgen_public_ip" {
  description = "loadgen EC2 public IP — SSH 접속해 k6 실행"
  value       = aws_instance.loadgen.public_ip
}

output "rds_endpoint" {
  description = "RDS endpoint (backend 가 자동 연결, Performance Insights 는 콘솔에서 관찰)"
  value       = aws_db_instance.main.endpoint
}

output "next_steps" {
  description = "부하테스트 진행 순서"
  value       = <<-EOT
    1) backend 부팅 확인:  curl http://${aws_instance.backend.public_ip}:8080/actuator/health
    2) 대량 시드:          curl -X POST http://${aws_instance.backend.public_ip}:8080/loadtest/seed -H 'Content-Type: application/json' -d '{"userCount":1000,"matchesPerUser":300}'
    3) loadgen SSH 접속 후 k6 스크립트 실행 (target = http://${aws_instance.backend.private_ip}:8080)
    4) 종료:               terraform destroy
  EOT
}
