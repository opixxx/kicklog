#!/usr/bin/env bash
# 보면서 부하 걸기 — 백엔드를 원하는 구성으로 띄우고 램프를 돌리며 Grafana 로 실시간 관찰한다.
#
# run-measurement.sh 와 목적이 다르다. 저쪽은 평탄 구간의 통계를 깨끗하게 얻는 이산 측정이고,
# 이쪽은 **천장이 생기는 과정**을 시간축에서 눈으로 보는 것이다. 숫자를 채택할 때는 저쪽을 쓴다.
#
# 사용:
#   tools/loadtest/watch.sh baseline      # 스레드 200 · 플랫폼  (천장 400 rps 예상)
#   tools/loadtest/watch.sh threads800    # 스레드 800 · 플랫폼  (천장 1600 rps 예상)
#   tools/loadtest/watch.sh vthreads      # 가상 스레드          (스레드 천장 없음)
#   tools/loadtest/watch.sh pooled        # 커넥션 풀 통제군     (천장 400 rps 예상 — 불변)

set -euo pipefail

CONFIG="${1:-baseline}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DELAY_MS="${DELAY_MS:-500}"
GRAFANA="${GRAFANA_URL:-http://localhost:3000}"
PROM="${PROM_URL:-http://localhost:9090}"

# 구성별 노브와 램프의 기준 천장. 천장 = 스레드 상한 ÷ 지연 이므로 지연이 바뀌면 같이 바뀐다.
case "$CONFIG" in
  baseline)   THREADS=200; VIRTUAL=false; CLIENT=simple ;;
  threads800) THREADS=800; VIRTUAL=false; CLIENT=simple ;;
  vthreads)   THREADS=200; VIRTUAL=true;  CLIENT=simple ;;
  pooled)     THREADS=200; VIRTUAL=false; CLIENT=pooled ;;
  *) echo "❌ 알 수 없는 구성: ${CONFIG} (baseline|threads800|vthreads|pooled)" >&2; exit 1 ;;
esac

if [ "$VIRTUAL" = "true" ]; then
  # 가상 스레드에는 스레드 상한이 없다. 램프 기준값은 "어디까지 올려볼지"로만 쓴다.
  CEILING="${CEILING:-1500}"
else
  CEILING="${CEILING:-$(( THREADS * 1000 / DELAY_MS ))}"
fi

# ─── 관측 스택 확인 ──────────────────────────────────────────────────────────
if ! curl -s -o /dev/null --max-time 5 "${GRAFANA}/api/health"; then
  echo "❌ Grafana 가 떠 있지 않습니다."
  echo "   docker compose -f infra/loadtest-observability/docker-compose.yml up -d"
  exit 1
fi
if ! curl -s -o /dev/null --max-time 5 "${PROM}/-/ready"; then
  echo "❌ Prometheus 가 떠 있지 않습니다 (같은 compose 로 기동)."
  exit 1
fi

# ─── 백엔드 기동 ─────────────────────────────────────────────────────────────
# LOADTEST_CONFIG_LABEL 이 모든 백엔드 지표에 config 라벨로 붙는다.
# k6 쪽도 --tag config= 로 같은 값을 붙여, Grafana 의 구성 필터가 양쪽에 함께 걸린다.
LOADTEST_CONFIG_LABEL="$CONFIG" \
TOMCAT_MAX_THREADS="$THREADS" \
VIRTUAL_THREADS="$VIRTUAL" \
LOADTEST_HTTP_CLIENT="$CLIENT" \
  bash "${REPO_ROOT}/tools/loadtest/backend-ctl.sh" start

# ─── mock upstream 확인 ──────────────────────────────────────────────────────
if ! curl -s -o /dev/null --max-time 3 "http://localhost:9100/health"; then
  echo "❌ mock upstream 이 없습니다 (:9100)."
  echo "   node tools/loadtest/mock-upstream.mjs --port 9100 --workers 3 &"
  exit 1
fi

cat <<BANNER

────────────────────────────────────────────────────────────────
  구성       ${CONFIG}  (스레드 ${THREADS} · 가상 ${VIRTUAL} · 클라이언트 ${CLIENT})
  주입 지연  ${DELAY_MS}ms
  기준 천장  ${CEILING} rps   ← 램프는 이 값의 0.5배 → 1배 → 2배로 올린다
  대시보드   ${GRAFANA}/d/kicklog-loadtest?from=now-5m&to=now&refresh=2s&var-config=${CONFIG}
────────────────────────────────────────────────────────────────

  보게 될 것:
    ① 천장 아래 — 주입률과 처리량 두 선이 겹쳐 간다
    ② 천장 근처 — Tomcat 스레드가 상한에 닿고 p95 가 들썩인다
    ③ 천장 위   — 두 선이 벌어지고 버려진 요청이 쌓인다
                  **그 동안 CPU 는 한가하다** — 이게 요점이다

  총 4분 20초. 지금 대시보드를 열어두세요.

BANNER

# ─── 램프 실행 ───────────────────────────────────────────────────────────────
# experimental-prometheus-rw: k6 가 지표를 Prometheus 로 직접 밀어넣는다.
# 푸시 간격을 2s 로 맞춰 백엔드 스크레이프와 같은 해상도로 본다 —
# 어긋나면 두 선의 변화 시점이 서로 밀려 보여 인과를 잘못 읽는다.
K6_PROMETHEUS_RW_SERVER_URL="${PROM}/api/v1/write" \
K6_PROMETHEUS_RW_TREND_STATS='med,p(95),p(99),max' \
K6_PROMETHEUS_RW_PUSH_INTERVAL=2s \
DELAY_MS="$DELAY_MS" \
CEILING="$CEILING" \
  k6 run --no-usage-report \
    --out experimental-prometheus-rw \
    --tag config="$CONFIG" \
    "${REPO_ROOT}/infra/terraform-loadtest/k6/w-ext-ramp.js"

echo ""
echo "✅ 램프 종료 — 그래프는 남아 있습니다 (Prometheus 보존 24시간)"
echo "   스크린샷: tools/loadtest/grafana-shot.sh docs/research/scenario1/grafana/${CONFIG} now-10m now"
