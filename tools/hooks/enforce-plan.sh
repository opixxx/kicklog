#!/bin/bash
# tools/hooks/enforce-plan.sh  (PreToolUse: Edit|Write|NotebookEdit)
#
# 30줄 이상 변경 + EXEC_PLAN.md 없거나 <TODO:> 남은 상태에서 코드 편집 차단.
# "30줄 미만 작은 변경은 면제" 정책 (ADR-0001 정신: Ralph "계획은 일회용, 짧게").
# iOS 도 대상 (ADR-0012: 에이전트가 iOS 구현을 맡기 시작하면서 백엔드와 동일 규칙 적용).
#
# 코드 파일 판별:
#   백엔드: .kt, .kts, .gradle, .yml, .yaml, .sql
#   iOS:   .swift
#
# 그 외 (.md, docs/, .claude/ 등)는 무관.

set -e
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:${PATH:-}"

input=$(cat)
file_path=$(echo "$input" | jq -r '.tool_input.file_path // empty')

if [ -z "$file_path" ]; then
  exit 0
fi

# ─── 코드 파일 여부 판별 ─────────────────────────────────────────────────────
case "$file_path" in
  */backend/*.kt|*/backend/*.kts|*/backend/*.gradle|*/backend/*.yml|*/backend/*.yaml|*/backend/*.sql)
    ;;
  */ios/*.swift)
    ;;
  *)
    exit 0  # 비코드 파일 — enforce-plan 대상 아님
    ;;
esac

# ─── worktree 루트 찾기 ──────────────────────────────────────────────────────
dir=$(dirname "$file_path")
top=$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null || true)

if [ -z "$top" ]; then
  exit 0
fi

# 메인 디렉토리는 enforce-worktree.sh가 처리. 이 훅은 linked worktree 내부에서만.
if [ ! -f "$top/.git" ]; then
  exit 0
fi

# ─── 변경 규모 확인 (staged + unstaged + working) ─────────────────────────────
# 누적 diff 라인 수 (추가 + 삭제)
CHANGED_LINES=$(git -C "$top" diff HEAD --numstat 2>/dev/null | awk '{sum+=$1+$2} END {print sum+0}')

# 30줄 미만 → 면제
if [ "$CHANGED_LINES" -lt 30 ]; then
  exit 0
fi

# ─── EXEC_PLAN.md 검사 ───────────────────────────────────────────────────────
plan="$top/EXEC_PLAN.md"

if [ ! -L "$plan" ] && [ ! -f "$plan" ]; then
  reason="🚫 계획 없이 큰 코드 편집 금지 (변경 ${CHANGED_LINES}줄, 임계 30줄).

이 worktree에 EXEC_PLAN.md가 없습니다. 다음 명령으로 작업을 올바르게 시작하세요:

  bash scripts/start-task.sh <task-name> <type>

기존 작업을 재개하는 중이라면 worktree가 잘못 생성되었을 수 있습니다.
정리 후 재시작하세요.

작은 변경(30줄 미만)은 EXEC_PLAN 면제 — 즉시 편집 가능합니다."
  jq -n --arg r "$reason" '{decision:"block", reason:$r}'
  exit 0
fi

# symlink를 따라가서 실제 파일 검사
if grep -q '<TODO:' "$plan" 2>/dev/null; then
  unfilled=$(grep -c '<TODO:' "$plan" || true)
  reason="🚫 EXEC_PLAN에 <TODO:...> 마커가 ${unfilled}개 남아있습니다 (변경 ${CHANGED_LINES}줄).

먼저 다음 3섹션을 모두 채워야 코드 편집이 허용됩니다:
  1. 목표 (Goal) — 왜 이 변경?
  2. 접근 (Approach) — 시그니처 수준 (메서드·API·핵심 규칙)
  3. 검증 (Verification) — Bash 명령으로 완료 조건

플랜 파일: ${plan}"
  jq -n --arg r "$reason" '{decision:"block", reason:$r}'
  exit 0
fi

exit 0
