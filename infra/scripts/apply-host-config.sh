#!/bin/bash
# =============================================
# KickLog — 호스트 설정 적용 (박스 내부, 멱등)
# =============================================
# ADR-0015 D3: 박스의 OS 레벨 설정(nginx conf·TLS 인증서·AASA·systemd timer)을
# **배포 산출물로만** 바꾼다. 박스에 직접 손대면 저장소와 운영이 갈라지고,
# `terraform plan` 이 "No changes" 를 내는 거짓 안심이 생긴다
# (2026-10-10 점검에서 실제로 그랬다: 저장소 conf 에만 rate limit, 운영에만 AASA).
#
# 실행: SSM Run Command (root). cd.yml 의 deploy job 이 앱 헬스 체크 성공 후 호출한다.
# 수동 실행도 가능:
#   DEPLOY_STAGING_BUCKET=kicklog-deploy-staging-<acct> bash apply-host-config.sh
#
# 적용 순서가 중요하다 — 인증서가 먼저 있어야 새 nginx conf 가 `nginx -t` 를 통과한다.
#   1) 패키지  2) Origin CA 인증서  3) Cloudflare realip  4) nginx conf  5) AASA  6) 타이머

set -euo pipefail

REGION="${AWS_REGION:-ap-northeast-2}"
BUCKET="${DEPLOY_STAGING_BUCKET:?DEPLOY_STAGING_BUCKET 환경변수가 필요합니다}"

NGINX_CONF=/etc/nginx/conf.d/kicklog.conf
REALIP_CONF=/etc/nginx/conf.d/00-cloudflare-realip.conf
AASA_DIR=/var/www/kicklog/.well-known
BIN_DIR=/opt/kicklog/bin
STAMP=$(date -u +%Y%m%d-%H%M%S)

STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT

echo "===== 호스트 설정 적용 시작 $(date -Iseconds) ====="

# ─── 0) 산출물 수신 ───────────────────────────────────
aws s3 cp "s3://${BUCKET}/host/" "$STAGE/" --recursive --region "$REGION" --no-progress

# ─── 1) 필수 패키지 (멱등) ────────────────────────────
# jq: fetch-secrets.sh 가 DB secret JSON 파싱에 사용 (없으면 배포가 실패한다)
# postgresql16: pg-dump-to-s3.sh 용. 서버가 16 이라 15 클라이언트로는 덤프가 거부된다.
if ! rpm -q jq >/dev/null 2>&1; then
  echo "패키지 설치: jq"
  dnf install -y -q jq
fi

# ADR-0016: psql 클라이언트는 더 이상 설치하지 않는다 (DB 가 컨테이너 안에 있어
# `docker exec kicklog-postgres psql` 로 충분하고, 호스트/서버 버전 불일치도 사라진다).

# ─── 1-b) 데이터 볼륨 마운트 확인 (ADR-0016) ─────────
# 마운트가 풀린 채 compose 를 올리면 Postgres 가 빈 디렉토리에 새 클러스터를 만든다.
# 배포 경로에서 먼저 막는다 — 가장 위험한 실패 모드다.
PGDATA_MOUNT="${PGDATA_MOUNT:-/mnt/pgdata}"
if ! mountpoint -q "$PGDATA_MOUNT"; then
  echo "❌ 데이터 볼륨이 마운트되지 않았습니다: $PGDATA_MOUNT" >&2
  echo "   이 상태로 compose 를 올리면 빈 DB 가 생성됩니다. 적용을 중단합니다." >&2
  echo "   확인: lsblk / findmnt $PGDATA_MOUNT / mount -a" >&2
  exit 1
fi

# ─── 2) Cloudflare Origin CA 인증서 ───────────────────
bash "$STAGE/install-origin-cert.sh"

# ─── 3) 실제 클라이언트 IP 복원 (realip) ──────────────
# Cloudflare 프록시 뒤에서는 모든 요청의 remote_addr 이 엣지 IP 다.
# 이걸 복원하지 않으면 rate limit 이 전 사용자를 한 버킷으로 묶고,
# 로그·Sentry 의 클라이언트 IP 도 전부 엣지 IP 가 된다.
# 목록 조회가 실패하면 기존 파일을 유지한다 (빈 파일로 덮어쓰면 복원이 꺼진다).
TMP_REALIP="$STAGE/realip.conf"
{
  echo "# 자동 생성 — apply-host-config.sh ($(date -Iseconds))"
  echo "# 수동 수정 금지. 목록 출처: https://www.cloudflare.com/ips-v4 , ips-v6"
  if curl -fsS --max-time 10 https://www.cloudflare.com/ips-v4 > "$STAGE/ips-v4" &&
     curl -fsS --max-time 10 https://www.cloudflare.com/ips-v6 > "$STAGE/ips-v6"; then
    while read -r cidr; do [ -n "$cidr" ] && echo "set_real_ip_from $cidr;"; done < "$STAGE/ips-v4"
    while read -r cidr; do [ -n "$cidr" ] && echo "set_real_ip_from $cidr;"; done < "$STAGE/ips-v6"
    echo "real_ip_header CF-Connecting-IP;"
    echo "real_ip_recursive on;"
  else
    echo "__FETCH_FAILED__"
  fi
} > "$TMP_REALIP"

if grep -q "__FETCH_FAILED__" "$TMP_REALIP"; then
  if [ -f "$REALIP_CONF" ]; then
    echo "⚠️  Cloudflare IP 목록 조회 실패 — 기존 $REALIP_CONF 를 유지합니다." >&2
  else
    echo "❌ Cloudflare IP 목록 조회 실패 + 기존 파일 없음 — realip 없이 rate limit 을 켜면" >&2
    echo "   전 사용자가 한 버킷으로 묶입니다. 적용을 중단합니다." >&2
    exit 1
  fi
else
  install -m 0644 "$TMP_REALIP" "$REALIP_CONF"
  echo "realip 설정 갱신: $(grep -c set_real_ip_from "$REALIP_CONF") 개 레인지"
fi

# ─── 4) nginx conf 배치 (검증 게이트 + 자동 롤백) ─────
BACKUP=""
if [ -f "$NGINX_CONF" ]; then
  BACKUP="${NGINX_CONF}.bak-${STAMP}"
  cp -p "$NGINX_CONF" "$BACKUP"
fi

install -m 0644 "$STAGE/nginx-kicklog.conf" "$NGINX_CONF"
mkdir -p /var/www/certbot "$AASA_DIR"

if nginx -t 2>"$STAGE/nginx-t.err"; then
  systemctl reload nginx
  echo "nginx conf 적용 + reload 완료"
else
  echo "❌ nginx -t 실패:" >&2
  cat "$STAGE/nginx-t.err" >&2
  if [ -n "$BACKUP" ]; then
    cp -p "$BACKUP" "$NGINX_CONF"
    nginx -t && systemctl reload nginx
    echo "직전 conf 로 롤백했습니다: $BACKUP" >&2
  fi
  exit 1
fi

# 오래된 백업 정리 (최근 5개만 보존)
ls -1t "${NGINX_CONF}".bak-* 2>/dev/null | tail -n +6 | xargs -r rm -f

# ─── 5) AASA (Universal Link) ─────────────────────────
# nginx 가 root /var/www/kicklog 로 서빙하므로 .well-known 하위에 둔다.
if [ -f "$STAGE/apple-app-site-association" ]; then
  install -m 0644 "$STAGE/apple-app-site-association" "$AASA_DIR/apple-app-site-association"
  echo "AASA 배치 완료: $AASA_DIR/apple-app-site-association"
fi

# ─── 6) 운영 스크립트 + systemd timer ─────────────────
mkdir -p "$BIN_DIR"
for s in pg-dump-to-s3.sh check-cert-expiry.sh check-host-health.sh install-origin-cert.sh fetch-secrets.sh; do
  [ -f "$STAGE/$s" ] && install -m 0750 "$STAGE/$s" "$BIN_DIR/$s"
done

for unit in "$STAGE"/kicklog-*.service "$STAGE"/kicklog-*.timer; do
  [ -f "$unit" ] && install -m 0644 "$unit" "/etc/systemd/system/$(basename "$unit")"
done

systemctl daemon-reload
systemctl enable --now kicklog-pg-dump.timer kicklog-cert-check.timer kicklog-host-health.timer

echo "타이머 상태:"
systemctl list-timers --no-pager 'kicklog-*' || true

echo "===== 호스트 설정 적용 완료 $(date -Iseconds) ====="
