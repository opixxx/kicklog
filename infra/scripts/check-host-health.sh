#!/bin/bash
# =============================================
# KickLog — 호스트/컨테이너 상태 감시 (박스 내부, systemd timer 10분)
# =============================================
# ADR-0016: RDS 를 폐지하면서 CloudWatch 알람 3개가 사라졌다.
#   rds-low-storage        → 디스크 사용률로 대체
#   backend-db-disconnected → 컨테이너 health 로 대체 (2026-09-06 형 장애 감지의 핵심)
#   rds-high-cpu           → EC2 CPU 알람이 이미 커버
# 이 값들은 박스 로컬 상태라 CloudWatch 가 볼 수 없어, 박스가 직접 SNS 로 통보한다.
#
# 알림 폭주 방지: 문제 조합이 바뀌었을 때 또는 6시간 경과 시에만 발행한다.

set -uo pipefail

REGION="${AWS_REGION:-ap-northeast-2}"
TOPIC_NAME="${TOPIC_NAME:-kicklog-alerts}"
DISK_WARN_PCT="${DISK_WARN_PCT:-85}"
SWAP_WARN_PCT="${SWAP_WARN_PCT:-50}"
PGDATA_MOUNT="${PGDATA_MOUNT:-/mnt/pgdata}"
STATE_FILE=/var/lib/kicklog/host-health.state
COOLDOWN_SECONDS=21600 # 6시간

mkdir -p "$(dirname "$STATE_FILE")"
problems=()

# ─── 1) 데이터 볼륨 마운트 ────────────────────────────
# 가장 위험한 상태: 마운트가 풀린 채 Postgres 가 기동하면 빈 디렉토리에 새 클러스터를
# 만들어 "데이터가 사라진 것처럼" 보인다. 최우선으로 본다.
if ! mountpoint -q "$PGDATA_MOUNT"; then
  problems+=("데이터 볼륨 미마운트: $PGDATA_MOUNT — Postgres 를 기동하면 빈 DB 가 만들어질 수 있습니다")
fi

# ─── 2) 디스크 사용률 ─────────────────────────────────
while read -r target pct; do
  [ -z "$target" ] && continue
  if [ "$pct" -ge "$DISK_WARN_PCT" ]; then
    problems+=("디스크 사용률 ${pct}% (임계 ${DISK_WARN_PCT}%): $target")
  fi
done < <(df --output=target,pcent / "$PGDATA_MOUNT" 2>/dev/null | tail -n +2 | tr -d '%' | awk '{print $1, $2}')

# ─── 3) 컨테이너 상태 ─────────────────────────────────
for c in kicklog-postgres kicklog-backend; do
  if ! docker ps --format '{{.Names}}' | grep -qx "$c"; then
    problems+=("컨테이너 미실행: $c")
    continue
  fi
  health=$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "$c" 2>/dev/null)
  restarts=$(docker inspect --format '{{.RestartCount}}' "$c" 2>/dev/null)
  if [ "$health" != "healthy" ] && [ "$health" != "none" ]; then
    problems+=("컨테이너 비정상: $c (health=$health, restarts=$restarts)")
  fi
done

# ─── 4) 스왑 사용률 ───────────────────────────────────
# 스왑을 쓰기 시작했다는 것은 2GB 예산이 빡빡해졌다는 신호다 (2026-09-06 재발 조짐).
read -r swap_total swap_used < <(free -m | awk '/^Swap:/ {print $2, $3}')
if [ "${swap_total:-0}" -gt 0 ]; then
  swap_pct=$(( swap_used * 100 / swap_total ))
  if [ "$swap_pct" -ge "$SWAP_WARN_PCT" ]; then
    problems+=("스왑 사용률 ${swap_pct}% (${swap_used}/${swap_total}MB) — 메모리 예산 재검토 필요")
  fi
fi

# ─── 통보 ─────────────────────────────────────────────
if [ ${#problems[@]} -eq 0 ]; then
  echo "정상 — 문제 없음 $(date -Iseconds)"
  rm -f "$STATE_FILE"
  exit 0
fi

message=$(printf '%s\n' "${problems[@]}")
hash=$(printf '%s' "$message" | md5sum | cut -d' ' -f1)
now=$(date +%s)

should_notify=true
if [ -f "$STATE_FILE" ]; then
  read -r prev_hash prev_time < "$STATE_FILE"
  if [ "$prev_hash" = "$hash" ] && [ $((now - prev_time)) -lt "$COOLDOWN_SECONDS" ]; then
    should_notify=false
  fi
fi

echo "$message"

if [ "$should_notify" = true ]; then
  ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
  TOPIC_ARN="arn:aws:sns:${REGION}:${ACCOUNT_ID}:${TOPIC_NAME}"
  aws sns publish --region "$REGION" --topic-arn "$TOPIC_ARN" \
    --subject "[KickLog] 호스트 상태 경고" \
    --message "$(printf '%s\n\n--\n호스트: %s\n시각: %s\n' "$message" "$(hostname)" "$(date -Iseconds)")" >/dev/null \
    && echo "SNS 통보 발행" || echo "⚠️  SNS 발행 실패" >&2
  echo "$hash $now" > "$STATE_FILE"
else
  echo "(동일 문제 지속 — 쿨다운 중이라 통보 생략)"
fi

exit 1
