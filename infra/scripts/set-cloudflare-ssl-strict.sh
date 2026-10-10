#!/bin/bash
# =============================================
# KickLog — Cloudflare SSL 모드를 Full(strict) 로 전환 (로컬)
# =============================================
# ADR-0015 D1. 현재 모드가 full(비 strict) 이면 엣지가 오리진 인증서를 검증하지 않는다.
# 그래서 오리진 인증서가 46일간 만료돼 있어도 사용자에게는 200 이 내려갔다
# (= 깨진 걸 아무도 모르는 상태). strict 로 올리면 그 은폐가 사라진다.
#
# ⚠️ 반드시 오리진에 유효한 Origin CA 인증서가 설치된 뒤에 실행한다.
#    순서가 틀리면 엣지가 526(Invalid SSL certificate) 을 내려 서비스가 끊긴다.
# 롤백: MODE=full bash set-cloudflare-ssl-strict.sh

set -euo pipefail

REGION="${AWS_REGION:-ap-northeast-2}"
ZONE_NAME="${ZONE_NAME:-kicklog.org}"
MODE="${MODE:-strict}"

TOKEN=$(aws ssm get-parameter --region "$REGION" \
  --name /kicklog/cloudflare-api-token --with-decryption \
  --query Parameter.Value --output text)

ZONE_ID=$(curl -fsS "https://api.cloudflare.com/client/v4/zones?name=${ZONE_NAME}" \
  -H "Authorization: Bearer ${TOKEN}" | jq -r '.result[0].id')

echo "현재 SSL 모드: $(curl -fsS "https://api.cloudflare.com/client/v4/zones/${ZONE_ID}/settings/ssl" \
  -H "Authorization: Bearer ${TOKEN}" | jq -r '.result.value')"

RESULT=$(curl -fsS -X PATCH "https://api.cloudflare.com/client/v4/zones/${ZONE_ID}/settings/ssl" \
  -H "Authorization: Bearer ${TOKEN}" -H "Content-Type: application/json" \
  --data "{\"value\":\"${MODE}\"}")

echo "변경 후 SSL 모드: $(echo "$RESULT" | jq -r '.result.value')"
echo "엣지 확인: curl -s -o /dev/null -w '%{http_code}\n' https://${ZONE_NAME}/actuator/health"
