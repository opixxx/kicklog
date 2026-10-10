#!/bin/bash
# =============================================
# KickLog — 오리진 인증서 만료 감시 (박스 내부, systemd timer)
# =============================================
# 왜 필요한가 (ADR-0015):
#   2026-08-25 에 만료된 오리진 인증서를 46일 뒤에야 발견했다. 기존 CloudWatch
#   알람 6개는 전부 인프라 메트릭이라 인증서를 보지 않고, Cloudflare 가 Full(비 strict)
#   로 가려주고 있어 사용자 영향도 없어 무증상이었다.
#   Origin CA 는 15년이지만 "감시가 없다" 는 구조적 결함은 그대로이므로 감시를 둔다.
#
# 임계 이하이면 SNS 로 직접 발행한다 (박스 로컬 파일은 CloudWatch 알람으로 볼 수 없다).

set -euo pipefail

REGION="${AWS_REGION:-ap-northeast-2}"
CERT_PATH="${CERT_PATH:-/etc/ssl/cloudflare/origin.pem}"
WARN_DAYS="${WARN_DAYS:-21}"
TOPIC_ARN="${TOPIC_ARN:-}"

if [ -z "$TOPIC_ARN" ]; then
  TOPIC_ARN=$(aws sns list-topics --region "$REGION" \
    --query "Topics[?contains(TopicArn, 'kicklog-alerts')].TopicArn | [0]" --output text)
fi

notify() {
  echo "$1"
  if [ -n "$TOPIC_ARN" ] && [ "$TOPIC_ARN" != "None" ]; then
    aws sns publish --region "$REGION" --topic-arn "$TOPIC_ARN" \
      --subject "[KickLog] 오리진 인증서 점검 경고" --message "$1" >/dev/null
  else
    echo "⚠️  SNS topic 을 찾지 못해 통보를 보내지 못했습니다." >&2
  fi
}

if [ ! -f "$CERT_PATH" ]; then
  notify "오리진 인증서 파일이 없습니다: $CERT_PATH (nginx TLS 가 기동 불가 상태일 수 있음)"
  exit 1
fi

END_DATE=$(openssl x509 -in "$CERT_PATH" -noout -enddate | cut -d= -f2)
END_EPOCH=$(date -d "$END_DATE" +%s)
NOW_EPOCH=$(date +%s)
DAYS_LEFT=$(( (END_EPOCH - NOW_EPOCH) / 86400 ))

echo "인증서 만료: $END_DATE (잔여 ${DAYS_LEFT}일, 임계 ${WARN_DAYS}일)"

if [ "$DAYS_LEFT" -le "$WARN_DAYS" ]; then
  notify "오리진 인증서 잔여 ${DAYS_LEFT}일 (만료 $END_DATE). 갱신이 필요합니다: infra/scripts/issue-origin-cert.sh 참조."
fi
