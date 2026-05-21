# =============================================
# EC2 — Spring Boot 호스팅 인스턴스
# =============================================
# ADR-0006 D3: Amazon Linux 2023 + JDK 17 (일반 JVM)
# ADR-0006 D4: Docker + docker-compose로 Spring Boot 실행

# ─── EC2 Instance ─────────────────────────────────────
resource "aws_instance" "app" {
  ami           = data.aws_ami.amazon_linux_2023.id
  instance_type = var.ec2_instance_type
  subnet_id     = aws_subnet.public_a.id
  key_name      = var.ssh_key_name

  vpc_security_group_ids = [aws_security_group.ec2.id]
  iam_instance_profile   = aws_iam_instance_profile.ec2.name

  root_block_device {
    volume_size = var.ec2_volume_size_gb
    volume_type = "gp3"
    encrypted   = true

    tags = {
      Name = "kicklog-ec2-root"
    }
  }

  # 첫 부팅 시 Docker + docker-compose + nginx + certbot 설치
  user_data = file("${path.module}/user-data.sh")

  tags = {
    Name = "kicklog-ec2"
  }

  # user_data 변경 시 재생성 X (수동 SSH로 갱신)
  lifecycle {
    ignore_changes = [user_data, ami]
  }
}

# ─── Elastic IP (재부팅 시 IP 유지) ──────────────────
resource "aws_eip" "app" {
  domain   = "vpc"
  instance = aws_instance.app.id

  tags = {
    Name = "kicklog-eip"
  }

  depends_on = [aws_internet_gateway.main]
}

# ─── IAM Role: EC2가 Secrets Manager 읽기 권한 ────────
resource "aws_iam_role" "ec2" {
  name = "kicklog-ec2-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_instance_profile" "ec2" {
  name = "kicklog-ec2-profile"
  role = aws_iam_role.ec2.name
}

resource "aws_iam_role_policy" "ec2_secrets_read" {
  name = "kicklog-ec2-secrets-read"
  role = aws_iam_role.ec2.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret",
        ]
        Resource = [
          aws_secretsmanager_secret.db_password.arn,
          aws_secretsmanager_secret.kakao_rest_api_key.arn,
          aws_secretsmanager_secret.jwt_secret.arn,
        ]
      }
    ]
  })
}

# CloudWatch Logs 권한 (선택 — 로그 중앙화 시)
resource "aws_iam_role_policy_attachment" "ec2_cloudwatch" {
  role       = aws_iam_role.ec2.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}
