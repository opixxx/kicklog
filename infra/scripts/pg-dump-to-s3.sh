#!/bin/bash
# =============================================
# KickLog — pg_dump 논리 백업 → S3 (박스 내부, systemd timer)
# =============================================
# ADR-0015 D2: RDS 자동 스냅샷(7일)과 별도로 논리 백업을 둔다.
#   - 스냅샷은 계정·리전·KMS 키에 묶여 교차 계정 복원이 불가하다
#   - 테이블 1개만 되살리는 부분 복구가 안 된다
#   - pg_dump -Fc 는 로컬에서 pg_restore 로 열 수 있어 검증이 쉽다
#
# 접속정보는 Secrets Manager(kicklog/db-password) 에서 받는다 — .env 의존 없음.
# 주의: 서버가 PostgreSQL 16 이므로 pg_dump 도 16 이어야 한다 (15 는 거부당한다).

set -euo pipefail

REGION="${AWS_REGION:-ap-northeast-2}"
BUCKET="${BACKUP_BUCKET:-}"
RETAIN_NOTE="S3 lifecycle 이 30일 후 자동 삭제 (backup.tf)"

if [ -z "$BUCKET" ]; then
  ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
  BUCKET="kicklog-backup-${ACCOUNT_ID}"
fi

command -v pg_dump >/dev/null || { echo "pg_dump 가 없습니다. dnf install -y postgresql16" >&2; exit 1; }
command -v jq >/dev/null || { echo "jq 가 없습니다. dnf install -y jq" >&2; exit 1; }

echo "===== pg_dump 백업 시작 $(date -Iseconds) ====="

DB_JSON=$(aws secretsmanager get-secret-value --region "$REGION" \
  --secret-id kicklog/db-password --query SecretString --output text)

PGHOST=$(echo "$DB_JSON" | jq -r .host)
PGPORT=$(echo "$DB_JSON" | jq -r .port)
PGUSER=$(echo "$DB_JSON" | jq -r .username)
PGPASSWORD=$(echo "$DB_JSON" | jq -r .password)
PGDATABASE=$(echo "$DB_JSON" | jq -r .dbname)
export PGHOST PGPORT PGUSER PGPASSWORD PGDATABASE

STAMP=$(date -u +%Y%m%dT%H%M%SZ)
DUMP_FILE="/tmp/kicklog-${STAMP}.dump"
trap 'rm -f "$DUMP_FILE"' EXIT

# -Fc(custom) = 압축 + pg_restore 로 선택 복원 가능. --no-owner 로 복원 환경 의존 제거.
pg_dump -Fc --no-owner --no-privileges -f "$DUMP_FILE"

SIZE=$(stat -c %s "$DUMP_FILE")
if [ "$SIZE" -lt 1024 ]; then
  echo "❌ 덤프가 ${SIZE}바이트로 비정상적으로 작습니다 — 업로드하지 않습니다." >&2
  exit 1
fi

# 업로드 전에 덤프 자체를 검증한다 (목록을 읽을 수 없으면 복구에 못 쓴다).
pg_restore --list "$DUMP_FILE" > /dev/null

KEY="pg/kicklog-${STAMP}.dump"
aws s3 cp "$DUMP_FILE" "s3://${BUCKET}/${KEY}" --region "$REGION" --no-progress

echo "업로드 완료: s3://${BUCKET}/${KEY} ($(numfmt --to=iec "$SIZE" 2>/dev/null || echo "${SIZE}B"))"
echo "$RETAIN_NOTE"
echo "===== pg_dump 백업 완료 $(date -Iseconds) ====="
