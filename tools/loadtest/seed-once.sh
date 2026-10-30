#!/usr/bin/env bash
# W-DB 측정용 시드 — **1회만** 돌린다.
#
# 주입률마다 재시드하면 회차 사이에 테이블 크기가 달라져 쿼리 비용이 변한다. 그러면 처리량 차이를
# 설정 변경에 귀속할 수 없다. 그래서 시드는 한 번 하고, 사용자 id 범위를 파일로 남겨
# 이후 k6 실행은 전부 SKIP_SEED=true 로 같은 데이터를 쓴다.
#
# 사용:
#   tools/loadtest/seed-once.sh [users] [matches_per_user]
#   source <(tools/loadtest/seed-once.sh --export)    # 기존 범위를 env 로 로드
#
# 산출: .loadtest-run/seed.env  (SEEDED_USER_ID_FROM / SEEDED_USER_ID_TO)

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RUN_DIR="${RUN_DIR:-${REPO_ROOT}/.loadtest-run}"
SEED_ENV="${RUN_DIR}/seed.env"
BASE_URL="${BASE_URL:-http://localhost:8080}"

if [ "${1:-}" = "--export" ]; then
  [ -f "$SEED_ENV" ] || { echo "❌ 시드 기록 없음: ${SEED_ENV}" >&2; exit 1; }
  sed 's/^/export /' "$SEED_ENV"
  exit 0
fi

USERS="${1:-200}"
MATCHES="${2:-60}"
mkdir -p "$RUN_DIR"

echo "▶︎ 시드 — 사용자 ${USERS}명 × 경기 ${MATCHES}건 (쿼터 4) = 경기 $((USERS * MATCHES))건"

RESPONSE="$(curl -s --max-time 900 -X POST "${BASE_URL}/loadtest/seed" \
  -H 'content-type: application/json' \
  -d "{\"userCount\":${USERS},\"matchesPerUser\":${MATCHES},\"quartersPerMatch\":4}")"

echo "$RESPONSE" | python3 -c '
import json, sys, pathlib

raw = sys.stdin.read()
try:
    body = json.loads(raw)
except json.JSONDecodeError:
    print(f"시드 응답을 해석할 수 없습니다: {raw[:300]}", file=sys.stderr)
    sys.exit(1)

if "seededUserIdFrom" not in body:
    print(f"시드 실패: {body}", file=sys.stderr)
    sys.exit(1)

path = pathlib.Path(sys.argv[1])
path.write_text(
    f"SEEDED_USER_ID_FROM={body['seededUserIdFrom']}\n"
    f"SEEDED_USER_ID_TO={body['seededUserIdTo']}\n"
    "SKIP_SEED=true\n"
)
id_from = body["seededUserIdFrom"]
id_to = body["seededUserIdTo"]
matches = body["matchesCreated"]
quarters = body["quartersCreated"]
print(f"✅ 시드 완료 — users {id_from}~{id_to}, matches {matches}, quarters {quarters}")
print(f"   범위 기록: {path}")
' "$SEED_ENV"
