#!/bin/bash
# tools/hooks/guard-bash.sh  (PreToolUse: Bash)
#
# 위험하고 되돌리기 어려운 Bash 명령을 사전 차단한다.
#
# 차단 원칙:
#   - 파괴적이고 자동 복구 불가한 명령만 차단 (false positive 최소화)
#   - 일반 개발 명령은 통과
#   - 차단 시 사유와 함께 사용자 직접 승인 후 실행하라는 안내 포함
#
# 비상 탈출:
#   사용자가 명시적으로 위험을 인지하고 실행해야 한다면 터미널에서 직접 실행

set -e

input=$(cat)
cmd=$(echo "$input" | jq -r '.tool_input.command // empty')

# 명령 없으면 통과
if [ -z "$cmd" ]; then
  exit 0
fi

# ─── 위험 패턴 정의 (정규식 → 사유) ────────────────────────────────────────────
check_pattern() {
  local pattern="$1"
  local reason="$2"
  if echo "$cmd" | grep -qE "$pattern" 2>/dev/null; then
    local err="🚫 위험 명령 차단: ${reason}

명령:
  ${cmd}

이 명령은 파괴적이거나 되돌리기 어려워 하네스가 자동 차단했습니다.
정말로 필요하다면 사용자에게 명시적 승인을 받고 터미널에서 직접 실행하세요.
참조: tools/hooks/guard-bash.sh"
    jq -n --arg r "$err" '{decision:"block", reason:$r}'
    exit 0
  fi
}

# 파일시스템 파괴
check_pattern 'rm[[:space:]]+-[rRf]+[[:space:]]+/([[:space:]]|$)'        'rm -rf / (루트 삭제)'
check_pattern 'rm[[:space:]]+-[rRf]+[[:space:]]+~([[:space:]]|/|$)'      'rm -rf ~ (홈 디렉토리 삭제)'
check_pattern 'rm[[:space:]]+-[rRf]+[[:space:]]+\$HOME'                   'rm -rf $HOME 삭제'
check_pattern 'rm[[:space:]]+-[rRf]+[[:space:]]+\.([[:space:]]|$)'        'rm -rf . (현재 디렉토리 통째 삭제)'
check_pattern 'rm[[:space:]]+-[rRf]+[[:space:]]+\*'                       'rm -rf * (와일드카드 일괄 삭제)'

# Git 위험 작업
check_pattern 'git[[:space:]]+push[[:space:]].*(--force|-f)([[:space:]]|$)'  'git push --force / -f'
check_pattern 'git[[:space:]]+push[[:space:]].*--force-with-lease'           'git push --force-with-lease (의도적이면 터미널에서 직접 실행)'
check_pattern 'git[[:space:]]+reset[[:space:]]+--hard'                       'git reset --hard'
check_pattern 'git[[:space:]]+clean[[:space:]]+-[fdxFDX]+'                    'git clean -fd / -fx (untracked 파일 일괄 삭제)'
check_pattern 'git[[:space:]]+branch[[:space:]]+-D[[:space:]]'                'git branch -D (강제 삭제)'
check_pattern 'git[[:space:]]+checkout[[:space:]]+\.'                         'git checkout . (워킹트리 일괄 폐기)'
check_pattern 'git[[:space:]]+restore[[:space:]]+\.'                          'git restore . (워킹트리 일괄 폐기)'

# DB 파괴
check_pattern '\b(DROP|drop)[[:space:]]+(TABLE|table|DATABASE|database|SCHEMA|schema)\b'  'DDL DROP (TABLE/DATABASE/SCHEMA)'
check_pattern '\b(TRUNCATE|truncate)[[:space:]]+(TABLE|table)?'                            'TRUNCATE TABLE'
check_pattern '\b(DELETE|delete)[[:space:]]+(FROM|from)[[:space:]]+[a-zA-Z_]+[[:space:]]*("|'\''|;|$)'      '조건 없는 DELETE FROM (WHERE 누락)'
check_pattern '\b(UPDATE|update)[[:space:]]+[a-zA-Z_]+[[:space:]]+(SET|set)[^;"'\'']*("|'\''|;|$)'         '조건 없는 UPDATE (WHERE 누락 의심)'

# 시스템 파괴
check_pattern 'mkfs\.'                                'mkfs (파일시스템 포맷)'
check_pattern 'dd[[:space:]]+if=.*of=/dev/'           'dd of=/dev/* (디스크 직접 쓰기)'
check_pattern ':\(\)\s*\{\s*:\s*\|\s*:\s*&\s*\}\s*;'  'fork bomb'
check_pattern 'chmod[[:space:]]+(-R[[:space:]]+)?0?777'  'chmod 777 (전체 권한 부여)'
check_pattern 'chmod[[:space:]]+(-R[[:space:]]+)?[+]w[[:space:]]+/'  'chmod +w / (시스템 경로 권한 변경)'

# 네트워크 신뢰 파이프
check_pattern 'curl[^|]*\|[[:space:]]*(sudo[[:space:]]+)?(bash|sh|zsh|fish)([[:space:]]|$)'  'curl | sh (검증 안 된 스크립트 실행)'
check_pattern 'wget[^|]*\|[[:space:]]*(sudo[[:space:]]+)?(bash|sh|zsh|fish)([[:space:]]|$)'   'wget | sh (검증 안 된 스크립트 실행)'

# Docker 위험 (KickLog 적응)
check_pattern 'docker[[:space:]]+system[[:space:]]+prune[[:space:]]+--all'      'docker system prune --all (모든 캐시·볼륨 삭제)'
check_pattern 'docker[[:space:]]+volume[[:space:]]+rm[[:space:]]+kicklog-postgres-data'  'kicklog-postgres-data 볼륨 삭제 (DB 데이터 영구 손실)'

# 모든 검사 통과
exit 0
