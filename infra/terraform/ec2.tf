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
        # sentry_dsn 은 두 경로를 모두 커버한다:
        #   - tfvars 로 관리하는 경우   → aws_secretsmanager_secret.sentry_dsn (count=1)
        #   - 콘솔·CLI 로 수동 생성한 경우 → data.aws_secretsmanager_secret.sentry_dsn_existing
        # 2026-09-16: 실제로는 수동 생성돼 있었고 이 정책에서 누락돼 있었다. 그 결과
        # fetch-secrets.sh 의 GetSecretValue 가 AccessDenied 로 실패했지만 `2>/dev/null ||`
        # 가 에러를 삼켜 SENTRY_DSN 이 빈 값으로 주입됐고, Sentry 가 조용히 꺼져 있었다.
        Resource = concat(
          [
            aws_secretsmanager_secret.db_password.arn,
            aws_secretsmanager_secret.kakao_rest_api_key.arn,
            aws_secretsmanager_secret.jwt_secret.arn,
            aws_secretsmanager_secret.ghcr_pat.arn,
          ],
          aws_secretsmanager_secret.sentry_dsn[*].arn,
          data.aws_secretsmanager_secret.sentry_dsn_existing[*].arn,
        )
      }
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

# ─── 오리진 인증서 조회 + 알림 발행 권한 (ADR-0015) ──
# install-origin-cert.sh 가 Cloudflare Origin CA 인증서를 SSM SecureString 에서 받아
# /etc/ssl/cloudflare 에 설치하고, check-cert-expiry.sh 가 잔여일이 임계 이하면
# SNS 로 직접 통보한다 (CloudWatch 알람으로는 박스 로컬 인증서를 볼 수 없다).
resource "aws_iam_role_policy" "ec2_origin_cert_and_alerts" {
  name = "kicklog-ec2-origin-cert-and-alerts"
  role = aws_iam_role.ec2.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ReadOriginCertParameters"
        Effect = "Allow"
        Action = [
          "ssm:GetParameter",
          "ssm:GetParameters",
        ]
        Resource = [
          "arn:aws:ssm:${var.aws_region}:${data.aws_caller_identity.current.account_id}:parameter/kicklog/origin-cert",
          "arn:aws:ssm:${var.aws_region}:${data.aws_caller_identity.current.account_id}:parameter/kicklog/origin-key",
        ]
      },
      {
        # SecureString 복호화 — AWS 관리형 키(alias/aws/ssm) 를 SSM 경유로만 사용하도록 제한.
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
      {
        Sid      = "PublishOperationalAlerts"
        Effect   = "Allow"
        Action   = "sns:Publish"
        Resource = aws_sns_topic.alerts.arn
      },
    ]
  })
}
