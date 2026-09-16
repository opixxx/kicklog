#!/bin/bash
# tools/hooks/verify-and-block.sh  (Stop)
#
# 에이전트가 작업 종료를 선언할 때 계산적 센서를 실행하고, 실패 시 자가수정 루프를 강제한다.
# 카운터 파일로 반복 횟수 제한 (무한 루프 + 비용 폭증 방지).
#
# 동작:
#   1) worktree 내부 + 백엔드 또는 iOS 변경 있을 때만 동작 (ADR-0012: iOS 도 컴파일 센서 대상)
#   2) 카운터 확인 — MAX_ATTEMPTS 초과 시 에스컬레이션
#   3) 백엔드 변경 → compileKotlin / iOS 변경 → xcodebuild (test는 PR/CI 단계로 위임)
#   4) 실패 → decision:"block" + 에러 주입 (에이전트가 reasoning 재개)
#   5) 성공 → 카운터 리셋

set -e
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:${PATH:-}"

MAX_ATTEMPTS=3
COUNTER_DIR="/tmp/kicklog-selfheal"
mkdir -p "$COUNTER_DIR"

append_trajectory() {
  local event="$1"
  local detail="$2"
  local traj_dir="${top}/docs/agent/trajectories"
  local traj_file="${traj_dir}/$(date +%Y-%m).log"
  mkdir -p "$traj_dir"
  {
    echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] ${event}"
    echo "$detail"
    echo ""
  } >> "$traj_file"
}

input=$(cat)
cwd=$(echo "$input" | jq -r '.cwd // empty')
[ -z "$cwd" ] && cwd="$(pwd)"

# ─── 1) worktree 판별 ────────────────────────────────────────────────────────
top=$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null || true)
if [ -z "$top" ] || [ ! -f "$top/.git" ]; then
  # 메인 디렉토리 또는 레포 밖 → 자가수정 훅 대상 아님
  exit 0
fi

# ─── 1-1) 백엔드/iOS 변경이 있는지 확인 ───────────────────────────────────────
CHANGED_BACKEND=$(git -C "$top" diff HEAD --name-only 2>/dev/null | grep -E '^backend/.*\.(kt|kts|gradle)$' || true)
CHANGED_IOS=$(git -C "$top" diff HEAD --name-only 2>/dev/null | grep -E '^ios/.*\.swift$' || true)
if [ -z "$CHANGED_BACKEND" ] && [ -z "$CHANGED_IOS" ]; then
  # 소스 변경 없음 (문서만) → verify-and-block 대상 아님
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

# ─── 3) 계산적 센서 — 백엔드 compileKotlin / iOS xcodebuild (test는 PR 단계) ──
log_file="${top}/logs/verify-$(date +%Y%m%d-%H%M%S).log"
mkdir -p "${top}/logs"

failed_check=""
changed_files=""

if [ -n "$CHANGED_BACKEND" ]; then
  if ! (cd "$top/backend" && ./gradlew compileKotlin --quiet) > "$log_file" 2>&1; then
    failed_check="backend.compileKotlin"
    changed_files="$CHANGED_BACKEND"
  fi
fi

if [ -z "$failed_check" ] && [ -n "$CHANGED_IOS" ]; then
  if ! (cd "$top/ios" && xcodebuild build -project KickLog.xcodeproj -scheme KickLog \
        -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO -quiet) > "$log_file" 2>&1; then
    failed_check="ios.xcodebuild"
    changed_files="$CHANGED_IOS"
  fi
fi

if [ -z "$failed_check" ]; then
  if [ "$count" -gt 0 ]; then
    append_trajectory "SELF_HEAL_RESOLVED check=compile attempts=${count}" \
"- resolved_by: subsequent code changes
- prevention_required: decide whether this was one-off or should update docs/agent/learning.md, EXEC_PLAN template, code-reviewer, or backend-test-writer"
  fi
  # 성공 — 카운터 리셋
  rm -f "$counter_file"
  exit 0
fi

# ─── 4) 실패 — 자가수정 요청 ──────────────────────────────────────────────────
new_count=$((count + 1))
echo "$new_count" > "$counter_file"

err_tail=$(tail -30 "$log_file" 2>/dev/null || echo "(로그 없음)")

append_trajectory "SELF_HEAL_ATTEMPT check=${failed_check} attempt=${new_count}/${MAX_ATTEMPTS}" \
"- failure_type: compile
- failed_check: ${failed_check}
- log_file: ${log_file}
- changed_files:
$(echo "$changed_files" | sed 's/^/  - /')
- error_tail:
$(echo "$err_tail" | sed 's/^/  /')
- learning_action: after fixing, record root cause and prevention in docs/agent/learning.md if this can recur"

reason="❌ 컴파일 실패: ${failed_check} (시도 ${new_count}/${MAX_ATTEMPTS})

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
