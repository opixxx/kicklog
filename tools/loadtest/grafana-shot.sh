#!/usr/bin/env bash
# Grafana 패널을 PNG 로 렌더링한다 — 사람이 보는 그 대시보드에서 그대로 뽑는다.
#
# grafana-image-renderer 컨테이너가 헤드리스 크롬으로 그려 PNG 를 돌려준다.
# 브라우저를 띄울 수 없는 환경에서도 측정 결과를 그림으로 남길 수 있고,
# 사람이 화면에서 본 것과 같은 쿼리·같은 시간창이라 수치가 어긋나지 않는다.
#
# 사용:
#   tools/loadtest/grafana-shot.sh                     # 최근 10분, 기본 패널
#   tools/loadtest/grafana-shot.sh out/ now-30m now     # 출력 경로·시간창 지정
#   PANELS="8 13 14" tools/loadtest/grafana-shot.sh     # 특정 패널만

set -euo pipefail

OUT_DIR="${1:-${PWD}/docs/research/scenario1/grafana}"
FROM="${2:-now-10m}"
TO="${3:-now}"
GRAFANA="${GRAFANA_URL:-http://localhost:3000}"
UID_DASH="kicklog-loadtest"
WIDTH="${WIDTH:-1100}"
HEIGHT="${HEIGHT:-420}"
# 구성 필터. 비워두면 전 구성이 겹쳐 그려진다 — 회차 간 비교는 그 상태로 본다.
VAR_CONFIG="${VAR_CONFIG:-}"
VAR_PARAM=""
[ -n "$VAR_CONFIG" ] && VAR_PARAM="&var-config=${VAR_CONFIG}"

# 패널 id → 파일명. 대시보드 JSON 의 생성 순서대로 번호가 붙는다.
declare -a PANEL_IDS=(8 9 13 14 15 16)
declare -a PANEL_NAMES=(
  "01-throughput-vs-injection"
  "02-latency-distribution"
  "03-tomcat-threads"
  "04-cpu"
  "05-platform-threads"
  "06-hikaricp"
)

if [ -n "${PANELS:-}" ]; then
  read -r -a PANEL_IDS <<< "$PANELS"
  PANEL_NAMES=()
  for id in "${PANEL_IDS[@]}"; do PANEL_NAMES+=("panel-${id}"); done
fi

mkdir -p "$OUT_DIR"

if ! curl -s -o /dev/null --max-time 5 "${GRAFANA}/api/health"; then
  echo "❌ Grafana 에 접속할 수 없습니다: ${GRAFANA}" >&2
  echo "   기동: docker compose -f infra/loadtest-observability/docker-compose.yml up -d" >&2
  exit 1
fi

shot() {
  local url="$1" dest="$2" label="$3"
  local code
  # 렌더링은 헤드리스 크롬이 그리는 동안 걸린다 — 타임아웃을 넉넉히 둔다.
  code=$(curl -s -o "$dest" -w '%{http_code}' --max-time 90 "$url")
  if [ "$code" != "200" ]; then
    echo "  ❌ ${label} — HTTP ${code}" >&2
    # 실패 응답은 PNG 가 아니라 에러 본문이다. 남겨두면 "깨진 PNG"로 오해한다.
    head -c 300 "$dest" >&2; echo >&2
    rm -f "$dest"
    return 1
  fi
  # PNG 매직바이트 확인 — 200 이어도 에러 페이지가 올 수 있다.
  # od 의 출력 형식은 플랫폼마다 다르므로 바이트를 직접 비교한다.
  if ! python3 -c 'import sys; sys.exit(0 if open(sys.argv[1],"rb").read(8) == b"\x89PNG\r\n\x1a\n" else 1)' "$dest"; then
    echo "  ❌ ${label} — PNG 가 아님" >&2
    rm -f "$dest"
    return 1
  fi
  echo "  ✅ ${label} → ${dest} ($(wc -c < "$dest" | tr -d ' ') bytes)"
}

echo "📷 Grafana 렌더링 — ${FROM} ~ ${TO}"

FAILED=0
for i in "${!PANEL_IDS[@]}"; do
  id="${PANEL_IDS[$i]}"
  name="${PANEL_NAMES[$i]}"
  url="${GRAFANA}/render/d-solo/${UID_DASH}/x?orgId=1&panelId=${id}&from=${FROM}&to=${TO}&width=${WIDTH}&height=${HEIGHT}&tz=Asia%2FSeoul${VAR_PARAM}"
  shot "$url" "${OUT_DIR}/${name}.png" "$name" || FAILED=$((FAILED + 1))
done

# 대시보드 전체 — 한 장으로 전후 맥락을 같이 보기 위함.
url="${GRAFANA}/render/d/${UID_DASH}/x?orgId=1&from=${FROM}&to=${TO}&width=1500&height=2100&kiosk&tz=Asia%2FSeoul${VAR_PARAM}"
shot "$url" "${OUT_DIR}/00-dashboard.png" "00-dashboard" || FAILED=$((FAILED + 1))

echo ""
if [ "$FAILED" -gt 0 ]; then
  echo "⚠️  ${FAILED}건 실패 — 렌더러 로그: docker logs kicklog-grafana-renderer --tail 30"
  exit 1
fi
echo "✅ 완료 — ${OUT_DIR}"
