#!/bin/bash
# tools/hooks/enforce-worktree.sh  (PreToolUse: Edit|Write|NotebookEdit)
#
# main/master 브랜치의 메인 작업 디렉토리에서 백엔드 소스 코드 직접 수정을 차단한다.
# 문서·하네스 설정·CI 파일은 예외 허용.
# iOS 는 보호 대상 아님 (사용자가 Xcode 에서 자유롭게 작업).

set -e

input=$(cat)
file_path=$(echo "$input" | jq -r '.tool_input.file_path // empty')

if [ -z "$file_path" ]; then
  exit 0
fi

# ─── 예외 화이트리스트 (메인 디렉토리에서도 허용) ──────────────────────────────
# 문서 / 하네스 / 스크립트 / CI / 레포 설정 / iOS 전체 (보호 대상 아님)
case "$file_path" in
  */docs/*|*.md|*.MD|*/CLAUDE.md|*/AGENTS.md|*/AGENT.md|*/CLAUDE.local.md|*/.claude/*|*/.codex/*|*/tools/hooks/*|*/tools/templates/*|*/scripts/*|*/.github/*|*/.githooks/*|*/\.gitignore|*/\.gitattributes|*/\.editorconfig|*/README.md|*/ios/*)
    exit 0
    ;;
esac

# ─── git 상태 확인 ────────────────────────────────────────────────────────────
dir=$(dirname "$file_path")
top=$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null || true)

if [ -z "$top" ]; then
  exit 0
fi

# linked worktree → 허용
if [ -f "$top/.git" ]; then
  exit 0
fi

# 메인 디렉토리 + main/master 브랜치 → 차단
branch=$(git -C "$top" branch --show-current)
if [ "$branch" = "main" ] || [ "$branch" = "master" ]; then
  # 백엔드 코드 파일인지 확인
  # 백엔드: .kt .kts .gradle .yml .yaml .properties .sql
  case "$file_path" in
    */backend/*.kt|*/backend/*.kts|*/backend/*.gradle|*/backend/*.yml|*/backend/*.yaml|*/backend/*.properties|*/backend/*.sql)
      ;;
    *)
      exit 0
      ;;
  esac

  task_hint=$(basename "$file_path" | sed 's/\..*//' | tr '[:upper:]' '[:lower:]')
  reason="🚫 보호 규칙 위반: ${branch} 브랜치의 메인 작업 디렉토리에서 백엔드 소스 직접 수정 금지.

대상 파일: ${file_path}

다음 명령으로 worktree를 생성한 뒤 해당 경로에서 작업을 재개하세요:

  bash scripts/start-task.sh <task-name> feature

예:
  bash scripts/start-task.sh ${task_hint} feature

이 스크립트는 worktree · EXEC_PLAN · 포트 · 로그 디렉토리를 원자적으로 생성합니다.

예외 (이 훅이 차단 안 함):
  - 문서 (*.md, docs/**)
  - 하네스 (CLAUDE.md, AGENTS.md, .claude/**, .codex/**, tools/**, scripts/**)
  - CI (.github/**, .githooks/**)
  - iOS 전체 (ios/**)  ← 보호 대상 아님
  - 레포 설정 (.gitignore, .gitattributes, .editorconfig)"

  jq -n --arg r "$reason" '{decision:"block", reason:$r}'
  exit 0
fi

exit 0
