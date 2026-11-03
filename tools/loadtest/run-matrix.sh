#!/usr/bin/env bash
# 시나리오 1 후보 비교 매트릭스 — 같은 jar, 설정만 교체하며 전 구성을 연속 측정한다.
#
# 각 구성의 주입률 집합은 **예측 천장을 끼고** 고른다. 천장 아래만 재면 평탄화가 안 보이고,
# 천장 위만 재면 선형 구간이 없어 Little's Law 교차검증을 못 한다.
#
# 예측 천장 (지연 500ms, 플랫폼 스레드 모델에서 천장 = threads.max ÷ 지연):
#   threads 200 → 400 rps      threads 800 → 1,600 rps      가상 스레드 → 스레드 천장 없음
#
# 사용: tools/loadtest/run-matrix.sh [구성명...]      (미지정 시 전 구성)

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CTL="${REPO_ROOT}/tools/loadtest/backend-ctl.sh"
RUN="${REPO_ROOT}/tools/loadtest/run-measurement.sh"
export DURATION="${DURATION:-25s}"
export DELAY_MS="${DELAY_MS:-500}"

run_config() {
  local label="$1"; shift
  local rates="$1"; shift
  # 남은 인자는 env 지정 (KEY=VALUE)
  echo ""
  echo "════════════════════════════════════════════════════════════"
  echo "  구성: ${label}   (주입률: ${rates})"
  echo "════════════════════════════════════════════════════════════"

  env "$@" bash "$CTL" start
  local desc
  desc="$(bash "$CTL" desc)"

  # shellcheck disable=SC2086
  BACKEND_DESC="$desc" bash "$RUN" "$label" $rates
}

want() {
  [ $# -eq 0 ] && return 0
  local target="$1"; shift
  for a in "$@"; do [ "$a" = "$target" ] && return 0; done
  return 1
}

SELECTED=("$@")

# ① 기준선 — 운영 형상 (스레드 200, 커넥션 풀 없는 클라이언트, 플랫폼 스레드).
#    효과 비교의 원점이다.
if want baseline-d500 "${SELECTED[@]}"; then
  run_config baseline-d500 "100 200 300 400 500 700 1000" \
    TOMCAT_MAX_THREADS=200 VIRTUAL_THREADS=false LOADTEST_HTTP_CLIENT=simple
fi

# ② 후보 ① 스레드 증설 200 → 800.
#    천장을 4배로 밀 수 있는지(= 천장이 정말 스레드인지) 확인하는 **효과 상한 측정**이다.
#    천장이 1,600 근처로 옮겨가면 "구속 자원 = 스레드" 가 확정된다.
if want threads800-d500 "${SELECTED[@]}"; then
  run_config threads800-d500 "400 800 1200 1600 2000" \
    TOMCAT_MAX_THREADS=800 VIRTUAL_THREADS=false LOADTEST_HTTP_CLIENT=simple
fi

# ③ 후보 ② 가상 스레드 — 지연과 스레드 수의 비례 관계 자체를 끊는다.
#    요청당 캐리어 스레드를 점유하지 않으므로 천장이 threads.max 에 묶이지 않는다.
if want vthreads-d500 "${SELECTED[@]}"; then
  run_config vthreads-d500 "400 800 1600 2400 3000" \
    TOMCAT_MAX_THREADS=200 VIRTUAL_THREADS=true LOADTEST_HTTP_CLIENT=simple
fi

# ④ 통제군 — 스레드는 200 그대로 두고 **커넥션 클라이언트만** 풀링으로 바꾼다.
#    천장이 그대로 400 이면 "천장은 커넥션 관리가 아니라 스레드"임이 분리 확인된다.
#    이 통제군이 없으면 ③의 개선을 커넥션 풀 효과와 구분할 수 없다.
if want pooled-d500 "${SELECTED[@]}"; then
  run_config pooled-d500 "200 400 600 800" \
    TOMCAT_MAX_THREADS=200 VIRTUAL_THREADS=false LOADTEST_HTTP_CLIENT=pooled
fi

echo ""
echo "✅ 매트릭스 완료"
for d in "${REPO_ROOT}"/docs/research/scenario1/*/summary.csv; do
  echo ""
  echo "── $(basename "$(dirname "$d")") ──"
  column -s, -t < "$d"
done
