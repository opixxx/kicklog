#!/usr/bin/env bash
# 시나리오 1 측정 러너 — 주입률을 이산적으로 올리며 처리량 천장을 찾는다.
#
# 설계 의도:
#   1) **이산 측정**  — 램프는 전이 구간이 평탄 구간 통계에 섞인다. 주입률 1개 = k6 실행 1회.
#   2) **drop 분리**  — open model 이라 처리 못 한 양(dropped_iterations)을 반드시 함께 기록한다.
#                      이걸 빼면 "처리량이 평탄하다"와 "주입을 못 받고 있다"를 구분할 수 없다.
#   3) **자원 동시 샘플링** — 포화 시점의 CPU·스레드·커넥션을 같이 찍는다. 이게 없으면
#                      천장이 하드웨어인지 설정인지 귀속할 수 없다 (판정 기준 G6).
#
# 사용:
#   tools/loadtest/run-measurement.sh <label> [rates...]
#   tools/loadtest/run-measurement.sh baseline-simple 250 500 750 1000 1500 2000 3000
#
# 결과: docs/research/scenario1/<label>/{summary.csv, r<rate>.json, r<rate>.metrics}

set -euo pipefail

LABEL="${1:?label 을 지정하세요 (예: baseline-simple)}"
shift || true
RATES=("$@")
if [ ${#RATES[@]} -eq 0 ]; then
  RATES=(250 500 750 1000 1500 2000 3000)
fi

DURATION="${DURATION:-30s}"
DELAY_MS="${DELAY_MS:-200}"
BASE_URL="${BASE_URL:-http://localhost:8080}"
# actuator 는 별도 관리 포트다 — 포화 구간에도 지표를 읽기 위함.
MGMT_URL="${MGMT_URL:-http://localhost:8081}"
WORKLOAD="${WORKLOAD:-w-ext}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="${REPO_ROOT}/infra/terraform-loadtest/k6/${WORKLOAD}.js"
OUT_DIR="${REPO_ROOT}/docs/research/scenario1/${LABEL}"

mkdir -p "$OUT_DIR"

# ─── 측정 전 환경 기록 ────────────────────────────────────────────────────────
# 어떤 설정에서 난 수치인지 남기지 않으면 회차 간 비교가 불가능해진다.
{
  echo "label=${LABEL}"
  echo "measured_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "workload=${WORKLOAD}  duration=${DURATION}  delay_ms=${DELAY_MS}"
  echo "warmup=${WARMUP_RATE:-${RATES[0]}} iters/s × ${WARMUP_DURATION:-10s} (결과 폐기)"
  echo "rates=${RATES[*]}"
  echo "--- backend 설정 (actuator env 대신 메트릭으로 확인 가능한 값) ---"
  for m in tomcat.threads.config.max; do
    echo "${m}=$(curl -s "${MGMT_URL}/actuator/metrics/${m}" \
      | python3 -c 'import sys,json;print(json.load(sys.stdin)["measurements"][0]["value"])' 2>/dev/null || echo "n/a")"
  done
  echo "--- host ---"
  echo "ncpu=$(sysctl -n hw.ncpu 2>/dev/null || nproc)"
  # 백엔드가 어떤 JVM·설정으로 떠 있는지는 러너가 알 수 없다(actuator 가 env 를 노출하지 않음).
  # 호출자가 BACKEND_DESC 로 명시해야 회차 간 비교가 가능하다 — 미지정이면 측정값의 귀속이 불가능하므로 경고.
  echo "backend_desc=${BACKEND_DESC:-⚠️ 미지정 — 백엔드 JVM·노브를 알 수 없어 비교 불가}"
  echo "runner_java=$(${JAVA_BIN:-java} -version 2>&1 | head -1)  # ← 러너 셸의 java, 백엔드와 다를 수 있음"
} > "${OUT_DIR}/env.txt"

echo "📁 결과: ${OUT_DIR}"
cat "${OUT_DIR}/env.txt"

CSV="${OUT_DIR}/summary.csv"
echo "rate,achieved_rps,dropped_per_s,dropped_total,fail_ratio,p50_ms,p95_ms,p99_ms,max_ms,vus_max,threads_busy_max,jvm_threads_max,cpu_proc_max,cpu_sys_max,hikari_active_max" > "$CSV"

# ─── 자원 샘플러 ──────────────────────────────────────────────────────────────
sample_metrics() {
  local out="$1"
  : > "$out"
  while true; do
    local line=""
    for m in tomcat.threads.busy jvm.threads.live process.cpu.usage system.cpu.usage hikaricp.connections.active; do
      v=$(curl -s --max-time 2 "${MGMT_URL}/actuator/metrics/${m}" \
        | python3 -c 'import sys,json;print(json.load(sys.stdin)["measurements"][0]["value"])' 2>/dev/null || echo "")
      line="${line}${v:-nan},"
    done
    echo "${line%,}" >> "$out"
    sleep 1
  done
}

# ─── 워밍업 ───────────────────────────────────────────────────────────────────
# 재기동 직후 첫 회차에는 JIT 컴파일·클래스 로딩·커넥션 풀 초기화가 섞인다.
# 실측 예: 같은 주입률 400 에서 첫 회차 cpu_proc 0.353 vs 워밍업 이후 0.039 — 9배 차이다.
# 천장 판정은 포화 구간에서 나오므로 결론은 흔들리지 않지만, CPU 를 회차 간 비교하려면
# 모든 구성이 같은 워밍업 상태에서 출발해야 한다.
WARMUP_RATE="${WARMUP_RATE:-${RATES[0]}}"
WARMUP_DURATION="${WARMUP_DURATION:-10s}"
if [ "$WARMUP_DURATION" != "skip" ]; then
  echo ""
  echo "🔥 워밍업 ${WARMUP_RATE} iters/s × ${WARMUP_DURATION} (결과 폐기)"
  RATE="$WARMUP_RATE" DURATION="$WARMUP_DURATION" DELAY_MS="$DELAY_MS" BASE_URL="$BASE_URL" \
    SUMMARY_PATH="" \
    k6 run --quiet --no-usage-report "$SCRIPT" > "${OUT_DIR}/warmup.k6.log" 2>&1 || {
      echo "  ⚠️  워밍업 실패 — 로그: warmup.k6.log"
      grep -m1 'level=error' "${OUT_DIR}/warmup.k6.log" 2>/dev/null | sed 's/^/     /' || true
    }
fi

for RATE in "${RATES[@]}"; do
  echo ""
  echo "▶︎ 주입률 ${RATE} iters/s (${DURATION}, 지연 ${DELAY_MS}ms)"

  METRICS_FILE="${OUT_DIR}/r${RATE}.metrics"
  SUMMARY_FILE="${OUT_DIR}/r${RATE}.json"

  sample_metrics "$METRICS_FILE" &
  SAMPLER_PID=$!

  set +e
  RATE="$RATE" DURATION="$DURATION" DELAY_MS="$DELAY_MS" BASE_URL="$BASE_URL" \
    SUMMARY_PATH="$SUMMARY_FILE" \
    k6 run --quiet --no-usage-report "$SCRIPT" > "${OUT_DIR}/r${RATE}.k6.log" 2>&1
  K6_RC=$?
  set -e

  kill "$SAMPLER_PID" 2>/dev/null || true
  wait "$SAMPLER_PID" 2>/dev/null || true

  if [ $K6_RC -ne 0 ]; then
    echo "  ⚠️  k6 종료 코드 ${K6_RC} — 로그: r${RATE}.k6.log"
    grep -m1 'level=error' "${OUT_DIR}/r${RATE}.k6.log" 2>/dev/null | sed 's/^/     /' || true
  fi

  python3 - "$SUMMARY_FILE" "$METRICS_FILE" "$RATE" "$CSV" "$K6_RC" <<'PY'
import json, sys, math

summary_path, metrics_path, rate, csv_path, k6_rc = sys.argv[1:6]

try:
    with open(summary_path) as f:
        data = json.load(f)
except (FileNotFoundError, json.JSONDecodeError) as exc:
    # 요약이 없으면 그 회차는 측정되지 않았다. 빈 행이라도 남겨 "값이 없다"가 CSV 에 보이게 한다 —
    # 조용히 빠지면 곡선에 구멍이 생긴 것을 모른 채 읽게 된다.
    with open(csv_path, "a") as f:
        f.write(f"{rate},INVALID(no-summary),,,,,,,,,,,,,\n")
    print(f"  ❌ 무효 — k6 요약 없음 ({exc})")
    sys.exit(0)

m = data.get("metrics", {})

def val(name, key, default=0.0):
    try:
        return float(m[name]["values"][key])
    except Exception:
        return default

achieved = val("http_reqs", "rate")
dropped_rate = val("dropped_iterations", "rate")
dropped_total = val("dropped_iterations", "count")
fail_ratio = val("http_req_failed", "value", val("http_req_failed", "rate"))
# 워크로드 전용 Trend 가 있으면 그것을 쓴다 (setup 요청이 섞인 http_req_duration 대신).
# 없으면(w-ext 처럼 setup 이 없는 워크로드) http_req_duration 이 곧 워크로드 지연이다.
_dur_metric = "workload_duration" if "workload_duration" in m else "http_req_duration"
d = m.get(_dur_metric, {}).get("values", {})
p50 = float(d.get("med", 0.0))
p95 = float(d.get("p(95)", 0.0))
p99 = float(d.get("p(99)", d.get("p(95)", 0.0)))
mx = float(d.get("max", 0.0))
vus_max = val("vus_max", "max")

# 자원 샘플 — 각 열의 최댓값. 포화 여부는 피크로 판단한다.
cols = [[] for _ in range(5)]
try:
    with open(metrics_path) as f:
        for line in f:
            parts = line.strip().split(",")
            if len(parts) != 5:
                continue
            for i, p in enumerate(parts):
                try:
                    cols[i].append(float(p))
                except ValueError:
                    pass
except FileNotFoundError:
    pass

def cmax(i):
    return max(cols[i]) if cols[i] else float("nan")

# ── 유효성 검사 ──────────────────────────────────────────────────────────────
# 측정이 실제로 돌았는지 먼저 확인한다. k6 가 setup 에서 죽으면 http_reqs 에 setup 요청만 남아
# "그럴듯한 숫자"가 나온다 — 평탄화로 오독할 수 있는 가장 위험한 실패 모드다.
# 판별: VU 반복이 0 이면 워크로드가 한 번도 실행되지 않았다.
iterations = val("iterations", "count")
reasons = []
if k6_rc != "0":
    reasons.append(f"k6 종료코드 {k6_rc}")
if vus_max == 0 or iterations == 0:
    reasons.append(f"VU 반복 {iterations:.0f}건 — 워크로드 미실행")

if reasons:
    with open(csv_path, "a") as f:
        f.write(f"{rate},INVALID,,,,,,,,,,,,,\n")
    print("  ❌ 무효 — " + "; ".join(reasons))
    print("     이 회차는 채택하지 않는다. 로그를 보고 원인을 고친 뒤 재측정할 것.")
    sys.exit(0)

row = [
    rate,
    f"{achieved:.1f}", f"{dropped_rate:.1f}", f"{dropped_total:.0f}", f"{fail_ratio:.4f}",
    f"{p50:.1f}", f"{p95:.1f}", f"{p99:.1f}", f"{mx:.1f}", f"{vus_max:.0f}",
    f"{cmax(0):.0f}", f"{cmax(1):.0f}", f"{cmax(2):.3f}", f"{cmax(3):.3f}", f"{cmax(4):.0f}",
]
with open(csv_path, "a") as f:
    f.write(",".join(row) + "\n")

print(f"  처리량 {achieved:8.1f} rps | drop {dropped_rate:7.1f}/s | p95 {p95:8.1f}ms | "
      f"busy {cmax(0):4.0f} | cpu_proc {cmax(2):.2f} | cpu_sys {cmax(3):.2f}")
PY
done

echo ""
echo "✅ 완료 — ${CSV}"
column -s, -t < "$CSV"
