#!/bin/bash
# =============================================
# KickLog — pg_dump 논리 백업 → S3 (박스 내부, systemd timer)
# =============================================
# ADR-0015 에서 도입하고 ADR-0016 에서 경로를 바꿨다 — DB 가 RDS 에서 같은 박스의
# postgres 컨테이너로 옮겨졌으므로 `docker exec` 로 덤프한다.
#
# RDS 자동 스냅샷이 사라진 지금, **이 백업이 1차 복구 수단**이다. 따라서:
#   - 덤프가 비정상적으로 작으면 업로드하지 않는다
#   - 업로드 전에 pg_restore --list 로 열어본다 (검증 없는 백업은 백업이 아니다)
#   - 실패 시 systemd OnFailure 가 SNS 로 통보한다 (kicklog-backup-failed.service)
#
# 복원 절차: docs/runbook/rds-restore-rehearsal.md

set -euo pipefail

REGION="${AWS_REGION:-ap-northeast-2}"
CONTAINER="${PG_CONTAINER:-kicklog-postgres}"
BUCKET="${BACKUP_BUCKET:-}"

if [[ -z "$BUCKET" ]]; then
  ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
  BUCKET="kicklog-backup-${ACCOUNT_ID}"
fi

echo "===== pg_dump 백업 시작 $(date -Iseconds) ====="

# 컨테이너가 살아 있어야 한다. 죽어 있으면 백업 실패로 통보되는 것이 맞다
# (조용히 건너뛰면 "백업이 도는 줄 알았는데 없었다" 가 된다).
if ! docker ps --format '{{.Names}}' | grep -qx "$CONTAINER"; then
  echo "❌ $CONTAINER 컨테이너가 실행 중이 아닙니다 — 백업할 수 없습니다." >&2
  exit 1
fi

STAMP=$(date -u +%Y%m%dT%H%M%SZ)
DUMP_FILE="/tmp/kicklog-${STAMP}.dump"
trap 'rm -f "$DUMP_FILE"' EXIT

# -Fc(custom): 압축 + pg_restore 로 선택 복원 가능. --no-owner: 복원 환경 의존 제거.
docker exec "$CONTAINER" sh -c \
  'pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB" -Fc --no-owner --no-privileges' > "$DUMP_FILE"

SIZE=$(stat -c %s "$DUMP_FILE")
if [[ "$SIZE" -lt 1024 ]]; then
  echo "❌ 덤프가 ${SIZE}바이트로 비정상적으로 작습니다 — 업로드하지 않습니다." >&2
  exit 1
fi

# 업로드 전에 덤프를 열어본다 — 목록을 못 읽으면 복구에 쓸 수 없다.
docker exec -i "$CONTAINER" pg_restore --list < "$DUMP_FILE" > /dev/null

KEY="pg/kicklog-${STAMP}.dump"
aws s3 cp "$DUMP_FILE" "s3://${BUCKET}/${KEY}" --region "$REGION" --no-progress

echo "업로드 완료: s3://${BUCKET}/${KEY} ($(numfmt --to=iec "$SIZE" 2>/dev/null || echo "${SIZE}B"))"
echo "S3 lifecycle 이 30일 후 자동 삭제 (backup.tf)"
echo "===== pg_dump 백업 완료 $(date -Iseconds) ====="
