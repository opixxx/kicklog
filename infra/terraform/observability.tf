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

# ═══════════════════════════════════════════════════════
# 앱 레벨 장애 감지 (2026-09-06 9일 마비 후속)
#
# 기존 알람(StatusCheckFailed · CPU>=90%)은 "OS 는 살았는데 앱만 죽은" 상태를 못 잡는다.
# 실제 장애 당시 StatusCheck 는 정상이었고 CPU 는 53% 여서 알람이 한 건도 울리지 않았다.
# 아래 두 알람은 그 사각지대를 메운다. 둘 다 기존 메트릭을 쓰므로 추가 비용이 없다.
# ═══════════════════════════════════════════════════════

# ─── 백엔드 DB 연결 끊김 — 앱 다운의 직접 신호 ────────
# 정상 운영 시 HikariCP 가 커넥션을 상시 유지해 DatabaseConnections 는 10 근처로 고정된다.
# 이 값이 0 이면 앱이 DB 에 붙지 못하는 상태 — 앱 사망·기동 실패·네트워크 단절 중 하나다.
# 2026-09-06 장애에서는 23:00(KST)에 0 으로 떨어져 9일간 유지됐다. 이 알람이 있었다면
# 15분 만에 통보됐다.
#
# 15분(5분 × 3)을 두는 이유: 배포 중 컨테이너 재시작으로 1~2분간 0 이 될 수 있어 오탐 방지.
# treat_missing_data=breaching — 메트릭 자체가 사라지는 것도 비정상으로 본다.
resource "aws_cloudwatch_metric_alarm" "backend_db_disconnected" {
  alarm_name          = "kicklog-backend-db-disconnected"
  alarm_description   = "백엔드가 15분 이상 RDS 에 연결되어 있지 않음 — 앱 다운 의심"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 3
  threshold           = 1
  period              = 300
  statistic           = "Maximum"
  metric_name         = "DatabaseConnections"
  namespace           = "AWS/RDS"
  treat_missing_data  = "breaching"

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.main.identifier
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]

  tags = {
    Name = "kicklog-backend-db-disconnected"
  }
}

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
