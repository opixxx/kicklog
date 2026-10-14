# =============================================
# Observability — SNS + CloudWatch Alarms + Log Retention
# =============================================
# ADR-0009 D3: 비용 사고/장애를 빨리 감지한다.
#
# 알람 임계는 t3.micro/db.t3.micro Free Tier 운영 가정.
# CloudWatch 알람 10개까지 Free (현재 4개 사용) → 추가 비용 없음.
# SNS 는 첫 1,000 publication/m 까지 Free Tier 안에 들어옴 (실제 알람 폭증 시에만 과금 가능성).

# ─── SNS Topic: 운영 알림 ────────────────────────────
# ⚠️ SSE 를 켜지 않는다 — 켜면 CloudWatch 알람이 이 토픽에 발행하지 못한다. ADR-0013.
#
# 2026-09-16 실측으로 확인: `alias/aws/sns`(AWS 관리형 키)로 SSE 를 켠 상태에서
#   - IAM 사용자의 직접 publish  → 성공 (Published 1 / Delivered 1 / Failed 0)
#   - CloudWatch 알람의 publish → **발행 자체가 일어나지 않음**
# CloudWatch 가 암호화된 토픽에 발행하려면 KMS 키 정책에 `cloudwatch.amazonaws.com` 의
# kms:GenerateDataKey* / kms:Decrypt 가 필요한데, **AWS 관리형 키는 정책을 수정할 수 없다.**
# 그 결과 2026-05 구축 이래 모든 알람이 조용히 실패하고 있었다 (알람은 ALARM 으로 바뀌지만
# 통보가 나가지 않음 — 알람이 있는데 아무도 모르는 최악의 상태).
#
# 대안이었던 고객 관리형 CMK 는 월 $1 + 호출 과금이라 free-tier 원칙에 어긋난다.
# 본 토픽의 메시지는 알람 이름·메트릭 값·시각뿐이고 PII/secret 이 없으며,
# 최종 전달 경로인 이메일(SMTP) 자체가 평문이라 SSE 의 실질 보안 이득이 거의 없다.
# → 통보 도달을 우선한다. 정적 분석(SonarQube)이 이 토픽의 미암호화를 지적하면
#   ADR-0013 을 근거로 예외 처리한다.
resource "aws_sns_topic" "alerts" {
  name = "kicklog-alerts"

  tags = {
    Name = "kicklog-alerts"
  }
}

# alert_email 이 빈 문자열이면 subscription 자체를 생성하지 않는다.
# (분리된 변수 사용 — 빈 값 ≠ subscription = 0)
resource "aws_sns_topic_subscription" "alerts_email" {
  count = var.alert_email == "" ? 0 : 1

  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email

  # SNS email 구독은 사용자가 확인 메일에서 confirm 해야 활성화됨 (terraform 으로 자동화 불가).
}

# ─── CloudWatch Alarms — EC2 ─────────────────────────
# StatusCheckFailed: 인스턴스 자체가 죽거나 도달 불가 (system + instance 통합).
resource "aws_cloudwatch_metric_alarm" "ec2_status_check_failed" {
  alarm_name          = "kicklog-ec2-status-check-failed"
  alarm_description   = "EC2 인스턴스 StatusCheck 실패 — 인스턴스 또는 시스템 장애"
  namespace           = "AWS/EC2"
  metric_name         = "StatusCheckFailed"
  statistic           = "Maximum"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  threshold           = 1
  period              = 60
  evaluation_periods  = 2
  datapoints_to_alarm = 2
  treat_missing_data  = "breaching"

  dimensions = {
    InstanceId = aws_instance.app.id
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]

  tags = {
    Name = "kicklog-ec2-status-check-failed"
  }
}

# CPUUtilization 90% 5분 — t3 burstable credit 고갈 신호.
resource "aws_cloudwatch_metric_alarm" "ec2_high_cpu" {
  alarm_name          = "kicklog-ec2-high-cpu"
  alarm_description   = "EC2 CPU >= 90% — t3 burstable credit 고갈 가능"
  namespace           = "AWS/EC2"
  metric_name         = "CPUUtilization"
  statistic           = "Average"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  threshold           = 90
  period              = 60
  evaluation_periods  = 5
  datapoints_to_alarm = 3
  treat_missing_data  = "notBreaching"

  dimensions = {
    InstanceId = aws_instance.app.id
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]

  tags = {
    Name = "kicklog-ec2-high-cpu"
  }
}

# ─── RDS 알람은 ADR-0016 으로 제거됐다 ───────────────
# rds-high-cpu / rds-low-storage / backend-db-disconnected 세 알람은 RDS 메트릭에
# 의존했는데 RDS 자체가 사라졌다. 역할은 이렇게 넘겼다:
#   - DB 과부하        → EC2 CPUUtilization 알람 (위)
#   - 스토리지 고갈     → check-host-health.sh 가 디스크 사용률 85% 초과 시 SNS
#   - 앱↔DB 단절(앱 사망) → check-host-health.sh 의 컨테이너 health 점검
#                          + 엣지 헬스 체크 Lambda (아래, ADR-0015)
# backend-db-disconnected 는 2026-09-06 형 장애를 잡는 핵심이었으므로
# 대체 수단 없이 지우지 않았다.

# ─── 디스크 읽기 폭증 — 메모리 스래싱 조기 경보 ───────
# 메모리가 고갈되면 커널이 page cache 를 버렸다 디스크에서 다시 읽기를 반복한다(스래싱).
# 이때 읽기량이 폭증하는데, 이것이 서비스가 완전히 멎기 전에 나타나는 가장 이른 신호다.
#
# 실측 기준(2026-09):
#   정상        0.01 ~ 0.4 GB/일  = 5분당 약 36KB ~ 1.4MB
#   스래싱 시   1,293 GB/일       = 5분당 약 4.5GB
# 임계 1GB/5분 은 정상의 700배 이상이자 스래싱의 1/4.5 수준 — 오탐 없이 조기에 잡힌다.
#
# 이 알람이 있었다면 8/22 에 울렸다. 실제 붕괴(9/6)보다 15일 빠르다.
resource "aws_cloudwatch_metric_alarm" "ec2_disk_read_surge" {
  alarm_name          = "kicklog-ec2-disk-read-surge"
  alarm_description   = "EBS 읽기량이 15분 연속 5분당 1GB 초과 — 메모리 스래싱 의심"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  threshold           = 1073741824 # 1 GiB
  period              = 300
  statistic           = "Sum"
  metric_name         = "VolumeReadBytes"
  namespace           = "AWS/EBS"
  treat_missing_data  = "notBreaching"

  dimensions = {
    VolumeId = aws_instance.app.root_block_device[0].volume_id
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]

  tags = {
    Name = "kicklog-ec2-disk-read-surge"
  }
}

# ─── CloudWatch Log Group — userdata / 배포 로그 ──────
# 본 그룹은 미래에 CloudWatch agent 가 활성화될 때 default "Never expire" 로 비용 폭증되는 것을 막는 안전망.
# 30 일 retention — Free Tier 5GB storage/m 안에 충분 (user-data 1회 ~5KB × 일1회 × 30일 ≈ 150KB).
# audit/compliance 관점에서도 단기 incident 추적에 적절 (SonarQube hotspot 정공법 해소).
resource "aws_cloudwatch_log_group" "userdata" {
  name              = "/kicklog/userdata"
  retention_in_days = 30

  tags = {
    Name = "kicklog-userdata-logs"
  }
}

# ═══════════════════════════════════════════════════════
# 엣지 헬스 체크 (ADR-0015 — 2026-10-10 TLS 46일 만료 방치 후속)
#
# 위 알람들은 모두 "AWS 가 보는 인프라" 를 본다. 그래서 다음을 못 잡는다:
#   - nginx 만 사망 (EC2 StatusCheck 정상 · DB 커넥션 정상)
#   - Cloudflare 엣지 장애 / 설정 실수
#   - TLS 인증서 만료 (실제로 46일간 무증상이었다)
# Lambda 가 VPC 밖에서 사용자와 동일한 경로를 5분마다 호출해 메꾼다.
# 비용: Lambda 월 8,640회(무료 한도 100만) + 커스텀 메트릭 2개(무료 10개) = $0
# ═══════════════════════════════════════════════════════

data "archive_file" "edge_health" {
  type        = "zip"
  source_file = "${path.module}/lambda/edge_health.py"
  output_path = "${path.module}/lambda/edge_health.zip"
}

resource "aws_iam_role" "edge_health" {
  name = "kicklog-edge-health-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })

  tags = {
    Name = "kicklog-edge-health-role"
  }
}

# 최소 권한 — 로그 기록 + 커스텀 메트릭 발행만. VPC 접근도 주지 않는다.
resource "aws_iam_role_policy" "edge_health" {
  name = "kicklog-edge-health-policy"
  role = aws_iam_role.edge_health.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents",
        ]
        Resource = "${aws_cloudwatch_log_group.edge_health.arn}:*"
      },
      {
        Effect   = "Allow"
        Action   = "cloudwatch:PutMetricData"
        Resource = "*"
        Condition = {
          StringEquals = {
            "cloudwatch:namespace" = "KickLog/Edge"
          }
        }
      },
    ]
  })
}

# 로그 그룹을 Lambda 보다 먼저 만들어 retention 을 강제한다
# (Lambda 가 자동 생성하면 "Never expire" 가 되어 장기 비용이 샌다).
resource "aws_cloudwatch_log_group" "edge_health" {
  name              = "/aws/lambda/kicklog-edge-health"
  retention_in_days = 14

  tags = {
    Name = "kicklog-edge-health-logs"
  }
}

resource "aws_lambda_function" "edge_health" {
  function_name = "kicklog-edge-health"
  description   = "외부에서 kicklog.org 엣지 상태를 5분마다 확인 (ADR-0015)"
  role          = aws_iam_role.edge_health.arn
  handler       = "edge_health.handler"
  runtime       = "python3.12"
  architectures = ["arm64"] # Graviton — 동일 성능에 요금 20% 저렴

  filename         = data.archive_file.edge_health.output_path
  source_code_hash = data.archive_file.edge_health.output_base64sha256

  timeout     = 15 # 프로브 타임아웃 10초 + 여유
  memory_size = 128

  environment {
    variables = {
      EDGE_HEALTH_URL = var.edge_health_url
    }
  }

  depends_on = [
    aws_iam_role_policy.edge_health,
    aws_cloudwatch_log_group.edge_health,
  ]

  tags = {
    Name = "kicklog-edge-health"
  }
}

resource "aws_cloudwatch_event_rule" "edge_health" {
  name                = "kicklog-edge-health-schedule"
  description         = "엣지 헬스 체크 5분 주기"
  schedule_expression = "rate(5 minutes)"

  tags = {
    Name = "kicklog-edge-health-schedule"
  }
}

resource "aws_cloudwatch_event_target" "edge_health" {
  rule      = aws_cloudwatch_event_rule.edge_health.name
  target_id = "kicklog-edge-health"
  arn       = aws_lambda_function.edge_health.arn
}

resource "aws_lambda_permission" "edge_health_events" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.edge_health.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.edge_health.arn
}

# 10분(5분 × 2) 연속 비정상이면 통보. 배포 중 순간 502 로 오탐하지 않을 만큼 길고,
# "9일간 아무도 모름" 같은 사태는 확실히 막을 만큼 짧다.
# treat_missing_data=breaching — Lambda 자체가 죽어 메트릭이 끊기는 것도 장애로 본다.
resource "aws_cloudwatch_metric_alarm" "edge_unhealthy" {
  alarm_name          = "kicklog-edge-unhealthy"
  alarm_description   = "외부에서 본 https://kicklog.org 가 10분 이상 비정상 — nginx/TLS/Cloudflare 경로 점검"
  namespace           = "KickLog/Edge"
  metric_name         = "EdgeHealthy"
  statistic           = "Minimum"
  comparison_operator = "LessThanThreshold"
  threshold           = 1
  period              = 300
  evaluation_periods  = 2
  datapoints_to_alarm = 2
  treat_missing_data  = "breaching"

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]

  tags = {
    Name = "kicklog-edge-unhealthy"
  }
}
