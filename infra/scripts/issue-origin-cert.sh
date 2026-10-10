#!/bin/bash
# =============================================
# KickLog — Cloudflare Origin CA 인증서 발급 (로컬, 1회성)
# =============================================
# ADR-0015 D1. Let's Encrypt/certbot 대체 — 유효기간 15년, 갱신 자동화 불필요.
#
# 사전 조건:
#   aws ssm put-parameter --name /kicklog/cloudflare-api-token --type SecureString \
#     --value '<토큰>' --region ap-northeast-2
#   토큰 권한: Zone:Read + Zone Settings:Edit + SSL and Certificates:Edit (kicklog.org)
#
# 동작:
#   1) 개인키 + CSR 생성 (로컬, 디스크에 남기지 않음)
#   2) Cloudflare Origin CA API 로 인증서 발급
#   3) cert/key 를 SSM SecureString 에 저장 (박스는 install-origin-cert.sh 로 받는다)
#   4) zone 의 SSL 모드를 strict 로 전환 (오리진 인증서를 실제로 검증하게 만든다)
#
# 재실행 안전: 새 인증서를 발급해 SSM 값을 갱신한다. 기존 인증서는 Cloudflare 측에
#   남아 있으나 사용되지 않는다(필요하면 대시보드에서 revoke).

set -euo pipefail

REGION="${AWS_REGION:-ap-northeast-2}"
ZONE_NAME="${ZONE_NAME:-kicklog.org}"
HOSTNAMES_JSON='["kicklog.org","*.kicklog.org"]'
VALIDITY_DAYS=5475 # 15년

command -v jq >/dev/null || { echo "jq 가 필요합니다 (brew install jq)" >&2; exit 1; }

echo "===== Origin CA 인증서 발급 시작 ====="

TOKEN=$(aws ssm get-parameter --region "$REGION" \
  --name /kicklog/cloudflare-api-token --with-decryption \
  --query Parameter.Value --output text)

api() { # api <METHOD> <PATH> [BODY] — API 토큰(Bearer) 경로
  local method="$1" path="$2" body="${3:-}"
  if [ -n "$body" ]; then
    curl -fsS -X "$method" "https://api.cloudflare.com/client/v4${path}" \
      -H "Authorization: Bearer ${TOKEN}" -H "Content-Type: application/json" --data "$body"
  else
    curl -fsS -X "$method" "https://api.cloudflare.com/client/v4${path}" \
      -H "Authorization: Bearer ${TOKEN}"
  fi
}

# Origin CA 발급(POST /certificates)은 계정에 따라 API 토큰 대신
# **Origin CA Key** (X-Auth-User-Service-Key) 를 요구한다. 두 경로를 모두 지원한다.
#   저장: aws ssm put-parameter --name /kicklog/cloudflare-origin-ca-key \
#           --type SecureString --value '<v1.0-...>' --region ap-northeast-2
#   확인 위치: dash.cloudflare.com → My Profile → API Tokens → 하단 "Origin CA Key" → View
api_origin_ca() { # api_origin_ca <BODY>
  local body="$1" out
  if out=$(curl -fsS -X POST "https://api.cloudflare.com/client/v4/certificates" \
      -H "Authorization: Bearer ${TOKEN}" -H "Content-Type: application/json" \
      --data "$body" 2>/dev/null); then
    echo "$out"
    return 0
  fi

  echo "ℹ️  API 토큰으로 Origin CA 발급이 거부됨 — Origin CA Key 로 재시도합니다." >&2
  local svc_key
  svc_key=$(aws ssm get-parameter --region "$REGION" \
    --name /kicklog/cloudflare-origin-ca-key --with-decryption \
    --query Parameter.Value --output text 2>/dev/null || true)

  if [ -z "$svc_key" ] || [ "$svc_key" = "None" ]; then
    echo "❌ /kicklog/cloudflare-origin-ca-key 가 없습니다." >&2
    echo "   dash.cloudflare.com → My Profile → API Tokens → 하단 Origin CA Key → View 로 확인 후" >&2
    echo "   SSM SecureString 으로 저장하고 다시 실행하세요." >&2
    echo "   (대안: 대시보드 SSL/TLS → Origin Server → Create Certificate 로 수동 발급)" >&2
    exit 1
  fi

  curl -fsS -X POST "https://api.cloudflare.com/client/v4/certificates" \
    -H "X-Auth-User-Service-Key: ${svc_key}" -H "Content-Type: application/json" \
    --data "$body"
}

ZONE_ID=$(api GET "/zones?name=${ZONE_NAME}" | jq -r '.result[0].id')
[ "$ZONE_ID" != "null" ] && [ -n "$ZONE_ID" ] || { echo "zone 조회 실패: $ZONE_NAME" >&2; exit 1; }
echo "zone_id=$ZONE_ID"

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# ECDSA P-256 — Origin CA 가 지원하고 RSA 대비 핸드셰이크가 가볍다.
openssl ecparam -name prime256v1 -genkey -noout -out "$WORK/origin.key" 2>/dev/null
openssl req -new -key "$WORK/origin.key" -subj "/CN=${ZONE_NAME}" -out "$WORK/origin.csr"

REQ=$(jq -n --arg csr "$(cat "$WORK/origin.csr")" --argjson hosts "$HOSTNAMES_JSON" \
  --argjson days "$VALIDITY_DAYS" \
  '{csr: $csr, hostnames: $hosts, request_type: "origin-ecc", requested_validity: $days}')

CERT=$(api_origin_ca "$REQ" | jq -r '.result.certificate')
[ -n "$CERT" ] && [ "$CERT" != "null" ] || { echo "인증서 발급 실패" >&2; exit 1; }
echo "$CERT" > "$WORK/origin.pem"
openssl x509 -in "$WORK/origin.pem" -noout -subject -enddate

aws ssm put-parameter --region "$REGION" --name /kicklog/origin-cert \
  --type SecureString --overwrite --value "file://$WORK/origin.pem" >/dev/null
aws ssm put-parameter --region "$REGION" --name /kicklog/origin-key \
  --type SecureString --overwrite --value "file://$WORK/origin.key" >/dev/null
echo "SSM 저장 완료: /kicklog/origin-cert, /kicklog/origin-key"

echo "다음: 박스에서 install-origin-cert.sh → nginx conf 적용 후 SSL 모드를 strict 로 올린다."
echo "      strict 전환 명령: bash set-cloudflare-ssl-strict.sh"
