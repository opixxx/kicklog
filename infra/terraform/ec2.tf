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

resource "aws_iam_role_policy" "ec2_ssm_read" {
  name = "kicklog-ec2-ssm-read"
  role = aws_iam_role.ec2.id

  # ADR-0016: Secrets Manager → SSM Parameter Store 일원화.
  # /kicklog/* 경로 전체를 허용한다 — terraform 이 만드는 비밀 5개와
  # 스크립트가 만드는 origin-cert/origin-key/cloudflare-api-token(ADR-0015)을
  # 한 정책으로 덮기 위함이다. 다른 경로는 읽을 수 없다.
  #
  # 2026-09-16 교훈(ADR-0015): ARN 을 개별 나열하다 sentry-dsn 이 빠져 Sentry 가
  # 조용히 꺼져 있었다. 경로 기반 권한이 그 실수 유형 자체를 없앤다.
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ReadKicklogParameters"
        Effect = "Allow"
        Action = [
          "ssm:GetParameter",
          "ssm:GetParameters",
          "ssm:GetParametersByPath",
        ]
        Resource = "arn:aws:ssm:${var.aws_region}:${data.aws_caller_identity.current.account_id}:parameter/kicklog/*"
      },
      {
        # SecureString 복호화 — AWS 관리형 키를 SSM 경유로만 쓰도록 제한.
        Sid      = "DecryptSecureStringViaSsm"
        Effect   = "Allow"
        Action   = "kms:Decrypt"
        Resource = "*"
        Condition = {
          StringEquals = {
            "kms:ViaService" = "ssm.${var.aws_region}.amazonaws.com"
          }
        }
      },
    ]
  })
}

# CloudWatch Logs 권한 (선택 — 로그 중앙화 시)
resource "aws_iam_role_policy_attachment" "ec2_cloudwatch" {
  role       = aws_iam_role.ec2.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

# SSM Run Command + Session Manager 권한 (ADR-0008).
# AL2023 AMI 에 SSM Agent 가 기본 설치되어 있어 user-data 변경 불필요.
resource "aws_iam_role_policy_attachment" "ec2_ssm_managed" {
  role       = aws_iam_role.ec2.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# 배포 스테이징 버킷에서 docker-compose.prod.yml 다운로드 권한 (ADR-0008).
# ADR-0015: apply-host-config.sh 가 host/ prefix 를 통째로 받으려면 ListBucket 이 필요하다
# (`aws s3 cp --recursive` 는 내부적으로 ListObjectsV2 를 호출한다).
# 버킷 전체 열람을 주지 않고 host/ prefix 로만 제한한다.
resource "aws_iam_role_policy" "ec2_deploy_bucket_read" {
  name = "kicklog-ec2-deploy-bucket-read"
  role = aws_iam_role.ec2.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "GetDeployArtifacts"
        Effect   = "Allow"
        Action   = "s3:GetObject"
        Resource = "${aws_s3_bucket.deploy_staging.arn}/*"
      },
      {
        Sid      = "ListHostPrefixOnly"
        Effect   = "Allow"
        Action   = "s3:ListBucket"
        Resource = aws_s3_bucket.deploy_staging.arn
        Condition = {
          StringLike = {
            "s3:prefix" = ["host/", "host/*"]
          }
        }
      },
    ]
  })
}

# ─── 논리 백업 업로드 권한 (ADR-0015) ────────────────
# pg-dump-to-s3.sh 가 매일 pg_dump 결과를 올린다. 읽기/삭제는 주지 않는다 —
# 박스가 침해되어도 과거 백업을 지우지 못하게 쓰기 전용으로 둔다.
resource "aws_iam_role_policy" "ec2_backup_write" {
  name = "kicklog-ec2-backup-write"
  role = aws_iam_role.ec2.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "s3:PutObject"
      Resource = "${aws_s3_bucket.backup.arn}/pg/*"
    }]
  })
}

# ─── 운영 알림 발행 권한 (ADR-0015 · 0016) ──────────
# check-cert-expiry.sh / check-host-health.sh 가 임계 초과 시 직접 통보한다.
# (박스 로컬 상태 — 디스크 사용률·컨테이너 health·인증서 잔여일 — 은 CloudWatch 가 볼 수 없다)
resource "aws_iam_role_policy" "ec2_alerts" {
  name = "kicklog-ec2-alerts"
  role = aws_iam_role.ec2.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid      = "PublishOperationalAlerts"
      Effect   = "Allow"
      Action   = "sns:Publish"
      Resource = aws_sns_topic.alerts.arn
    }]
  })
}
