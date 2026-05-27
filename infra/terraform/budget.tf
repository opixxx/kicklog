# =============================================
# AWS Budgets — 월 예산 알람
# =============================================
# ADR-0009 D3: 실수로 NAT/ALB/Multi-AZ 생성 시 즉시 감지하기 위한 안전망.
#
# Budget 리소스 자체는 무료 (계정당 2개 이하 무료, 본 PR 은 1개만).
# 알림 SNS publication 도 Free Tier 안 (월 1,000건).
#
# notifications 는 SNS 와 email 동시 전달 — alert_email 이 비면 email 만 생략.

resource "aws_budgets_budget" "monthly" {
  name              = "kicklog-monthly-budget"
  budget_type       = "COST"
  limit_amount      = tostring(var.budget_monthly_usd)
  limit_unit        = "USD"
  time_unit         = "MONTHLY"
  time_period_start = "2026-01-01_00:00"

  # 80% actual — 청구가 임계 도달
  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 80
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_sns_topic_arns  = [aws_sns_topic.alerts.arn]
    subscriber_email_addresses = var.alert_email == "" ? [] : [var.alert_email]
  }

  # 100% actual — 한도 초과
  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_sns_topic_arns  = [aws_sns_topic.alerts.arn]
    subscriber_email_addresses = var.alert_email == "" ? [] : [var.alert_email]
  }

  # 100% forecast — 월말 예측치가 한도 초과
  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "FORECASTED"
    subscriber_sns_topic_arns  = [aws_sns_topic.alerts.arn]
    subscriber_email_addresses = var.alert_email == "" ? [] : [var.alert_email]
  }

  # Budget 에는 tags 사용 불가 (AWS API 제한) — 다른 리소스는 provider default_tags 로 자동 부여.
}
