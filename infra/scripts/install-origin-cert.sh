#!/bin/bash
# =============================================
# KickLog — Cloudflare Origin CA 인증서 설치 (박스 내부)
# =============================================
# SSM Parameter Store(SecureString) → /etc/ssl/cloudflare/{origin.pem,origin.key}
#
# 왜 Origin CA 인가 (ADR-0015 D1):
#   Let's Encrypt + certbot --nginx 는 Cloudflare 프록시 뒤에서 조용히 죽는다.
#   80/443 이 엣지로 흡수되고 오리진의 80 은 ACME 경로가 없어 HTTP-01 이 실패하는데,
#   certbot-renew.timer 가 disabled 라 실패조차 알려지지 않았다 → 46일 만료 방치.
#   Origin CA 인증서는 유효기간 15년이고 엣지만 신뢰하면 되므로 갱신 자동화가 불필요하다.
#
# 멱등: 이미 같은 내용이 설치돼 있으면 파일을 건드리지 않고 0 으로 종료한다
#       (nginx reload 를 유발하지 않기 위함).

set -euo pipefail

REGION="${AWS_REGION:-ap-northeast-2}"
CERT_DIR=/etc/ssl/cloudflare
CERT_PATH="$CERT_DIR/origin.pem"
KEY_PATH="$CERT_DIR/origin.key"

echo "===== Origin CA 인증서 설치 시작 $(date -Iseconds) ====="

mkdir -p "$CERT_DIR"
chmod 755 "$CERT_DIR"

fetch_param() {
  aws ssm get-parameter --region "$REGION" --name "$1" --with-decryption \
    --query Parameter.Value --output text
}

TMP_CERT=$(mktemp)
TMP_KEY=$(mktemp)
trap 'rm -f "$TMP_CERT" "$TMP_KEY"' EXIT

# 조회 실패는 즉시 중단 — 빈 인증서를 설치해 nginx 를 깨뜨리는 것이 최악이다.
fetch_param /kicklog/origin-cert > "$TMP_CERT"
fetch_param /kicklog/origin-key  > "$TMP_KEY"

# 최소 형식 검증 (잘린 값·에러 문자열이 들어오는 것을 방지)
openssl x509 -in "$TMP_CERT" -noout -subject >/dev/null
openssl pkey -in "$TMP_KEY" -noout >/dev/null

# 인증서와 키가 실제로 한 쌍인지 확인 (modulus 비교)
CERT_HASH=$(openssl x509 -in "$TMP_CERT" -noout -pubkey | openssl sha256)
KEY_HASH=$(openssl pkey -in "$TMP_KEY" -pubout | openssl sha256)
if [ "$CERT_HASH" != "$KEY_HASH" ]; then
  echo "❌ 인증서와 개인키가 한 쌍이 아닙니다 — 설치를 중단합니다." >&2
  exit 1
fi

if [ -f "$CERT_PATH" ] && cmp -s "$TMP_CERT" "$CERT_PATH" && [ -f "$KEY_PATH" ] && cmp -s "$TMP_KEY" "$KEY_PATH"; then
  echo "변경 없음 — 이미 최신 인증서가 설치돼 있습니다."
else
  install -m 0644 -o root -g root "$TMP_CERT" "$CERT_PATH"
  install -m 0600 -o root -g root "$TMP_KEY" "$KEY_PATH"
  echo "설치 완료: $CERT_PATH (0644) / $KEY_PATH (0600)"
fi

openssl x509 -in "$CERT_PATH" -noout -subject -enddate -issuer
echo "===== Origin CA 인증서 설치 완료 ====="
