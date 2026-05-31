#!/usr/bin/env sh
# nginx / backend 컨테이너의 :8080 소켓 상태를 캡처한다.
#
# 주의: compose 에선 nginx↔backend 가 docker bridge 로 통신하므로 TIME_WAIT 은
# 컨테이너 namespace 안에 쌓인다 (host 의 ss 로는 안 보임). 그래서 컨테이너의
# /proc/net/tcp 를 읽어 host 측 awk 로 집계한다 (패키지 설치 불필요).
#
# 운영(prod)은 같은 박스 loopback(127.0.0.1)이라 위치만 다를 뿐 메커니즘은 동일.
#
# 사용: sh observe.sh   (compose 가 떠 있는 상태에서)
set -eu

COMPOSE="docker compose -f docker-compose.loadtest.yml"
NGINX=$($COMPOSE ps -q nginx)
BACKEND=$($COMPOSE ps -q backend)

# /proc/net/tcp(+tcp6) 필드4 st(hex): 01=ESTABLISHED, 06=TIME_WAIT, 0A=LISTEN. 포트8080=0x1F90.
# Tomcat 이 IPv6 wildcard 로 listen / IPv4-mapped 로 accept 하는 경우까지 tcp6 도 함께 읽는다.
# (헤더 줄은 $4 가 "st" 라 상태 hex 매칭에서 자연 제외됨)
count() { # $1=container  $2=state_hex
  docker exec "$1" sh -c 'cat /proc/net/tcp /proc/net/tcp6 2>/dev/null' \
    | awk -v st="$2" '($2 ~ /:1F90$/ || $3 ~ /:1F90$/) && $4==st {c++} END{print c+0}'
}

echo "==================================================="
echo " :8080 소켓 상태 (TIME_WAIT=재사용 안 됨 / ESTAB=영속 풀)"
echo "==================================================="
printf "  [nginx]   ESTAB=%s  TIME_WAIT=%s\n"   "$(count "$NGINX" 01)"   "$(count "$NGINX" 06)"
printf "  [backend] ESTAB=%s  TIME_WAIT=%s  LISTEN=%s\n" \
  "$(count "$BACKEND" 01)" "$(count "$BACKEND" 06)" "$(count "$BACKEND" 0A)"
echo "---------------------------------------------------"
echo " 해석: S0(no-keepalive)=TIME_WAIT 누적·ESTAB 거의 0"
echo "       S2(keepalive)   =ESTAB 풀 유지·TIME_WAIT 소수"
