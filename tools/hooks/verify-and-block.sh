#!/bin/bash
# tools/hooks/verify-and-block.sh  (Stop)
#
# 에이전트가 작업 종료를 선언할 때 계산적 센서를 실행하고, 실패 시 자가수정 루프를 강제한다.
# 카운터 파일로 반복 횟수 제한 (무한 루프 + 비용 폭증 방지).
#
# 동작:
#   1) worktree 내부 + 백엔드 변경 있을 때만 동작 (iOS 빌드는 너무 무거워 제외)
#   2) 카운터 확인 — MAX_ATTEMPTS 초과 시 에스컬레이션
#   3) compileKotlin 실행 (test는 PR/CI 단계로 위임)
#   4) 실패 → decision:"block" + 에러 주입 (에이전트가 reasoning 재개)
#   5) 성공 → 카운터 리셋

set -e

MAX_ATTEMPTS=3
COUNTER_DIR="/tmp/kicklog-selfheal"
mkdir -p "$COUNTER_DIR"

input=$(cat)
cwd=$(echo "$input" | jq -r '.cwd // empty')
[ -z "$cwd" ] && cwd="$(pwd)"

# ─── 1) worktree 판별 ────────────────────────────────────────────────────────
top=$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null || true)
if [ -z "$top" ] || [ ! -f "$top/.git" ]; then
  # 메인 디렉토리 또는 레포 밖 → 자가수정 훅 대상 아님
  exit 0
fi

# ─── 1-1) 백엔드 변경이 있는지 확인 ───────────────────────────────────────────
CHANGED_BACKEND=$(git -C "$top" diff HEAD --name-only 2>/dev/null | grep -E '^backend/.*\.(kt|kts|gradle)$' || true)
if [ -z "$CHANGED_BACKEND" ]; then
  # 백엔드 변경 없음 (iOS만 또는 문서만) → verify-and-block 대상 아님
  exit 0
fi

# 카운터 파일은 worktree별로 격리
counter_key=$(echo "$top" | tr '/' '_')
counter_file="${COUNTER_DIR}/${counter_key}"
count=$(cat "$counter_file" 2>/dev/null || echo 0)

# ─── 2) MAX 초과 시 에스컬레이션 ──────────────────────────────────────────────
if [ "$count" -ge "$MAX_ATTEMPTS" ]; then
  rm -f "$counter_file"
  reason="🛑 자가수정 ${MAX_ATTEMPTS}회 연속 실패 — 사람 개입이 필요합니다.

다음 형식으로 현재 상태를 사용자에게 보고하세요 (.claude/skills/orchestrator/references/escalation.md):

  - 사유: 자가수정 ${MAX_ATTEMPTS}회 실패
  - 현재까지 진행한 단계
  - 마지막으로 시도한 수정과 그 결과
  - 사용자에게 요청하는 결정"
  jq -n --arg r "$reason" '{decision:"block", reason:$r}'
  exit 0
fi

# ─── 3) 계산적 센서 — compileKotlin (test는 PR 단계) ─────────────────────────
log_file="${top}/logs/verify-$(date +%Y%m%d-%H%M%S).log"
mkdir -p "${top}/logs"

if (cd "$top/backend" && ./gradlew compileKotlin --quiet) > "$log_file" 2>&1; then
  # 성공 — 카운터 리셋
  rm -f "$counter_file"
  exit 0
fi

# ─── 4) 실패 — 자가수정 요청 ──────────────────────────────────────────────────
new_count=$((count + 1))
echo "$new_count" > "$counter_file"

err_tail=$(tail -30 "$log_file" 2>/dev/null || echo "(로그 없음)")

reason="❌ 백엔드 컴파일 실패 (시도 ${new_count}/${MAX_ATTEMPTS})

아래 에러를 분석하고 수정하세요:

\`\`\`
${err_tail}
\`\`\`

전체 로그: ${log_file}

금지 사항 (.claude/skills/orchestrator/references/self-heal-loop.md):
  - 테스트를 삭제하거나 skip 처리하여 우회
  - --no-verify, -DskipTests로 검증 우회
  - 원인 분석 없이 같은 수정 반복

힌트: orchestrator의 영역별 자동 위임 — backend 변경이면 code-reviewer 호출 가능"

jq -n --arg r "$reason" '{decision:"block", reason:$r}'
exit 0
