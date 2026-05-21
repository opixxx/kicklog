#!/bin/bash
# tools/hooks/session-context.sh  (SessionStart)
#
# 세션 시작 시 현재 작업 상태를 자동으로 컨텍스트에 주입한다.
# 사용자가 매번 "어디까지 했지?" 설명할 필요를 줄인다.
#
# 주입 정보:
#   - 현재 위치 (메인 디렉토리 vs linked worktree)
#   - 현재 브랜치
#   - 활성 EXEC_PLAN.md (worktree 안)
#   - 최근 커밋 5개
#   - 미커밋 변경 요약
#
# 출력: 30초 이상 걸리는 명령은 사용하지 않는다 (UserPromptSubmit과 달리 SessionStart는 600초 허용이지만 빠르게 유지).

set -e

input=$(cat 2>/dev/null || echo "{}")
cwd=$(echo "$input" | jq -r '.cwd // empty' 2>/dev/null || true)
[ -z "$cwd" ] && cwd="$(pwd)"

# ─── git 레포 외부면 컨텍스트 주입 생략 ──────────────────────────────────────
top=$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null || true)
if [ -z "$top" ]; then
  exit 0
fi

# ─── 위치 판별 (메인 vs linked worktree) ────────────────────────────────────
if [ -f "$top/.git" ]; then
  location="🔧 Linked worktree: $(basename "$top")"
  is_worktree=true
else
  location="📁 메인 작업 디렉토리"
  is_worktree=false
fi

# ─── 브랜치 ─────────────────────────────────────────────────────────────────
branch=$(git -C "$top" branch --show-current 2>/dev/null || echo "(detached)")

# ─── 활성 EXEC_PLAN ─────────────────────────────────────────────────────────
plan_info=""
if [ "$is_worktree" = true ]; then
  plan="$top/EXEC_PLAN.md"
  if [ -L "$plan" ] || [ -f "$plan" ]; then
    plan_target=$(readlink "$plan" 2>/dev/null || echo "$plan")
    todo_count=$(grep -c '<TODO:' "$plan" 2>/dev/null || echo "0")
    if [ "$todo_count" -gt 0 ]; then
      plan_info="📋 활성 EXEC_PLAN: ${plan_target} (⚠️ <TODO:> ${todo_count}개 미완성)"
    else
      plan_info="📋 활성 EXEC_PLAN: ${plan_target} (완성)"
    fi
  fi
fi

# ─── 최근 커밋 5개 ──────────────────────────────────────────────────────────
recent_commits=$(git -C "$top" log --oneline -5 2>/dev/null | sed 's/^/  /' || echo "  (커밋 없음)")

# ─── 미커밋 변경 ────────────────────────────────────────────────────────────
staged=$(git -C "$top" diff --cached --numstat 2>/dev/null | wc -l | tr -d ' ')
unstaged=$(git -C "$top" diff --numstat 2>/dev/null | wc -l | tr -d ' ')
untracked=$(git -C "$top" ls-files --others --exclude-standard 2>/dev/null | wc -l | tr -d ' ')
diff_summary="staged ${staged} · unstaged ${unstaged} · untracked ${untracked}"

# ─── 컨텍스트 조립 ──────────────────────────────────────────────────────────
context="${location}
브랜치: ${branch}"

if [ -n "$plan_info" ]; then
  context="${context}
${plan_info}"
fi

context="${context}

최근 커밋:
${recent_commits}

미커밋 변경: ${diff_summary}"

if [ "$is_worktree" = false ] && [ "$branch" = "main" ] && [ "$unstaged" -gt 0 -o "$staged" -gt 0 ]; then
  context="${context}

⚠️  main 브랜치 메인 디렉토리에 미커밋 변경이 있습니다. 코드 변경이면 worktree로 이동을 권장:
   bash scripts/start-task.sh <task-name> <type>"
fi

# ─── jq로 JSON 출력 ─────────────────────────────────────────────────────────
jq -n --arg c "$context" '{
  hookSpecificOutput: {
    hookEventName: "SessionStart",
    additionalContext: $c
  }
}'

exit 0
