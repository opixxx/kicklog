#!/usr/bin/env bash
# 측정용 백엔드 기동·종료 — **같은 jar, 설정만 교체**가 원칙이다.
#
# 회차마다 바이너리가 다르면 처리량 차이를 설정에 귀속할 수 없다. 그래서 jar 는 한 번만 빌드하고
# 이 스크립트는 env 만 바꿔 재기동한다.
#
# 가상 스레드는 **런타임** JDK 21+ 에서만 활성된다(빌드 toolchain 은 17 유지).
# 그래서 JAVA_BIN 을 JDK 21 로 고정해 기동한다 — 17 로 띄우면 VIRTUAL_THREADS=true 가
# 조용히 무시되고 플랫폼 스레드로 돌아, "가상 스레드를 켰는데 효과가 없다"는 오판을 낳는다.
#
# 사용:
#   tools/loadtest/backend-ctl.sh start                      # 기준선 (threads 200, simple, platform)
#   TOMCAT_MAX_THREADS=800 tools/loadtest/backend-ctl.sh start
#   VIRTUAL_THREADS=true tools/loadtest/backend-ctl.sh start
#   LOADTEST_HTTP_CLIENT=pooled tools/loadtest/backend-ctl.sh start
#   tools/loadtest/backend-ctl.sh stop
#   tools/loadtest/backend-ctl.sh desc                       # 현재 기동 설정 한 줄 요약

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
JAR="${JAR:-${REPO_ROOT}/backend/build/libs/kicklog-0.0.1-SNAPSHOT.jar}"
JAVA_BIN="${JAVA_BIN:-/Users/opix/Library/Java/JavaVirtualMachines/temurin-21.0.4/Contents/Home/bin/java}"
RUN_DIR="${RUN_DIR:-${REPO_ROOT}/.loadtest-run}"
PID_FILE="${RUN_DIR}/backend.pid"
LOG_FILE="${RUN_DIR}/backend.log"
DESC_FILE="${RUN_DIR}/backend.desc"

TOMCAT_MAX_THREADS="${TOMCAT_MAX_THREADS:-200}"
VIRTUAL_THREADS="${VIRTUAL_THREADS:-false}"
LOADTEST_HTTP_CLIENT="${LOADTEST_HTTP_CLIENT:-simple}"
DB_POOL_SIZE="${DB_POOL_SIZE:-10}"
HEAP="${HEAP:-2g}"
PORT="${SERVER_PORT:-8080}"
# actuator 전용 포트. 부하를 받는 PORT 와 분리해야 포화 구간에도 지표를 읽을 수 있다
# (같은 포트면 스크레이프가 부하 요청과 같은 스레드 풀에서 대기하다 타임아웃된다).
MGMT_PORT="${MANAGEMENT_PORT:-8081}"

mkdir -p "$RUN_DIR"

describe() {
  local jv
  jv="$("$JAVA_BIN" -version 2>&1 | head -1)"
  echo "jvm=[${jv}] heap=${HEAP} threads.max=${TOMCAT_MAX_THREADS} virtual=${VIRTUAL_THREADS} http-client=${LOADTEST_HTTP_CLIENT} db-pool=${DB_POOL_SIZE}"
}

stop_backend() {
  if [ -f "$PID_FILE" ]; then
    local pid
    pid="$(cat "$PID_FILE")"
    if kill -0 "$pid" 2>/dev/null; then
      echo "⏹  백엔드 종료 (pid=${pid})"
      kill "$pid" 2>/dev/null || true
      # graceful shutdown 을 기다린다. 강제 종료하면 커넥션이 TIME_WAIT 로 남아
      # 다음 회차의 기준선이 오염된다.
      for _ in $(seq 1 40); do
        kill -0 "$pid" 2>/dev/null || break
        sleep 0.5
      done
      kill -9 "$pid" 2>/dev/null || true
    fi
    rm -f "$PID_FILE"
  fi
  # pid 파일이 없는데 포트를 쓰고 있으면(수동 기동 등) 포트 점유 프로세스를 정리한다.
  # 이걸 안 하면 다음 기동이 bind 실패로 조용히 죽고, 측정은 **이전 설정의 백엔드**를 때린다 —
  # 가장 발견하기 어려운 종류의 측정 오류다.
  local owner
  owner="$(lsof -tiTCP:"$PORT" -sTCP:LISTEN -n 2>/dev/null | head -1 || true)"
  if [ -n "$owner" ]; then
    echo "⏹  포트 ${PORT} 점유 프로세스 정리 (pid=${owner})"
    kill "$owner" 2>/dev/null || true
    for _ in $(seq 1 40); do
      kill -0 "$owner" 2>/dev/null || break
      sleep 0.5
    done
    kill -9 "$owner" 2>/dev/null || true
  fi

  # 포트가 완전히 비워질 때까지 확인.
  for _ in $(seq 1 20); do
    lsof -iTCP:"$PORT" -sTCP:LISTEN -n >/dev/null 2>&1 || return 0
    sleep 0.5
  done
  echo "⚠️  포트 ${PORT} 가 아직 LISTEN 상태입니다" >&2
}

start_backend() {
  [ -f "$JAR" ] || { echo "❌ jar 없음: ${JAR} — ./gradlew bootJar 먼저 실행" >&2; exit 1; }
  [ -x "$JAVA_BIN" ] || { echo "❌ JAVA_BIN 실행 불가: ${JAVA_BIN}" >&2; exit 1; }

  stop_backend
  describe > "$DESC_FILE"
  echo "▶︎ 백엔드 기동 — $(cat "$DESC_FILE")"

  TOMCAT_MAX_THREADS="$TOMCAT_MAX_THREADS" \
  VIRTUAL_THREADS="$VIRTUAL_THREADS" \
  LOADTEST_HTTP_CLIENT="$LOADTEST_HTTP_CLIENT" \
  DB_POOL_SIZE="$DB_POOL_SIZE" \
  SERVER_PORT="$PORT" \
  MANAGEMENT_PORT="$MGMT_PORT" \
  nohup "$JAVA_BIN" -Xmx"$HEAP" -jar "$JAR" --spring.profiles.active=loadtest \
    > "$LOG_FILE" 2>&1 &
  echo $! > "$PID_FILE"

  if ! curl -s --retry 60 --retry-delay 1 --retry-connrefused --max-time 90 \
      -o /dev/null "http://localhost:${MGMT_PORT}/actuator/health"; then
    echo "❌ 기동 실패 — 로그: ${LOG_FILE}" >&2
    tail -20 "$LOG_FILE" >&2
    exit 1
  fi

  # 설정이 실제로 먹었는지 확인한다. env 를 줬다고 적용됐다고 믿으면 안 된다 —
  # 특히 VIRTUAL_THREADS 는 JDK 17 런타임에서 조용히 무시된다.
  local actual_max
  actual_max="$(curl -s "http://localhost:${MGMT_PORT}/actuator/metrics/tomcat.threads.config.max" \
    | python3 -c 'import sys,json;print(int(json.load(sys.stdin)["measurements"][0]["value"]))' 2>/dev/null || echo "?")"
  echo "✅ 기동 완료 — tomcat.threads.config.max=${actual_max} (요청값 ${TOMCAT_MAX_THREADS})"
  if [ "$VIRTUAL_THREADS" = "true" ]; then
    if grep -qiE 'virtual' "$LOG_FILE"; then
      echo "   가상 스레드 관련 로그 감지"
    fi
    echo "   ⚠️ 가상 스레드 활성 여부는 측정 중 jvm.threads.live 로 교차검증할 것"
    echo "      (플랫폼 스레드 모델이면 부하 시 live 가 busy 만큼 늘고, 가상이면 거의 늘지 않는다)"
  fi
}

case "${1:-}" in
  start) start_backend ;;
  stop) stop_backend; echo "✅ 종료" ;;
  restart) start_backend ;;
  desc) [ -f "$DESC_FILE" ] && cat "$DESC_FILE" || echo "기동 기록 없음" ;;
  *) echo "사용법: $0 {start|stop|restart|desc}" >&2; exit 1 ;;
esac
