# =============================================
# Observability — SNS + CloudWatch Alarms + Log Retention
# =============================================
# ADR-0009 D3: 비용 사고/장애를 빨리 감지한다.
#
# 알람 임계는 t3.micro/db.t3.micro Free Tier 운영 가정.
# CloudWatch 알람 10개까지 Free (현재 4개 사용) → 추가 비용 없음.
# SNS 는 첫 1,000 publication/m 까지 Free Tier 안에 들어옴 (실제 알람 폭증 시에만 과금 가능성).

# ─── SNS Topic: 운영 알림 ────────────────────────────
# SonarQube hotspot 해소 — AWS managed KMS key 로 SSE 활성화.
# `alias/aws/sns` 는 AWS 가 계정·region 별로 자동 생성·관리하며 추가 비용 없음.
# (고객 관리 CMK 는 월 $1 + API 호출 과금 — 본 토픽의 메시지(알람 메타데이터)는 PII/secret 없어 과잉)
resource "aws_sns_topic" "alerts" {
  name              = "kicklog-alerts"
  kms_master_key_id = "alias/aws/sns"

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

# ─── CloudWatch Alarms — RDS ─────────────────────────
resource "aws_cloudwatch_metric_alarm" "rds_high_cpu" {
  alarm_name          = "kicklog-rds-high-cpu"
  alarm_description   = "RDS CPU >= 85%"
  namespace           = "AWS/RDS"
  metric_name         = "CPUUtilization"
  statistic           = "Average"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  threshold           = 85
  period              = 60
  evaluation_periods  = 5
  datapoints_to_alarm = 3
  treat_missing_data  = "notBreaching"

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.main.identifier
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]

  tags = {
    Name = "kicklog-rds-high-cpu"
  }
}

# FreeStorageSpace <= 4GiB (20GB Free Tier 의 20%).
# Free Tier 스토리지가 작아 임계가 비교적 높지만, 사고 전 1주 정도 여유 보장.
resource "aws_cloudwatch_metric_alarm" "rds_low_storage" {
  alarm_name          = "kicklog-rds-low-storage"
  alarm_description   = "RDS FreeStorageSpace <= 4 GiB — Free Tier 20GB 한도 접근"
  namespace           = "AWS/RDS"
  metric_name         = "FreeStorageSpace"
  statistic           = "Minimum"
  comparison_operator = "LessThanOrEqualToThreshold"
  threshold           = 4 * 1024 * 1024 * 1024 # 4 GiB in bytes
  period              = 300
  evaluation_periods  = 2
  datapoints_to_alarm = 2
  treat_missing_data  = "notBreaching"

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.main.identifier
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]

  tags = {
    Name = "kicklog-rds-low-storage"
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
