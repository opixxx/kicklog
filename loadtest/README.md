# 경로 B 부하 테스트 하네스 — nginx ↔ backend keep-alive lifecycle

설계 SoT: [`../docs/research/keepalive-race-portfolio-scenario.md`](../docs/research/keepalive-race-portfolio-scenario.md)
운영 발견 근거(Step 0): [`../docs/research/assets/step0-prod-observation.md`](../docs/research/assets/step0-prod-observation.md)

```
k6 (host) ──> nginx (컨테이너) ──> backend (컨테이너, /loadtest/ping) ──> postgres
                  ▲ 여기 keep-alive 풀의 idle timeout 비대칭이 race 를 만든다
```

> 운영은 같은 박스 **loopback(127.0.0.1)**, 본 복제는 **docker bridge** 로 통신한다.
> 위치만 다를 뿐 keep-alive lifecycle 메커니즘은 동일하다. TIME_WAIT 은 컨테이너
> namespace 안에 쌓이므로 [`observe.sh`](./observe.sh) 가 컨테이너 `/proc/net/tcp` 를 읽는다.

---

## 사전 준비

```bash
brew install k6           # 부하 도구
docker --version          # compose v2 포함
cd loadtest
```

## 3막 상태 토글 (요약)

| 막 | nginx conf (NGINX_CONF) | backend (TOMCAT_KEEPALIVE_TIMEOUT) | 관찰 |
|---|---|---|---|
| **S0** ① loopback 낭비 | `./nginx/no-keepalive.conf` | (무관) | TIME_WAIT 누적 |
| **S1** ③ race | `./nginx/keepalive.conf` | `1s` (< nginx 60s) | 502 race |
| **S2** ④ 예방 | `./nginx/keepalive.conf` | `80s` (> nginx 60s) | 502 = 0 |

---

## Measurement A — TIME_WAIT before/after (claim: 수천 → 수십)

**A-1 (S0, before):**
```bash
NGINX_CONF=./nginx/no-keepalive.conf docker compose -f docker-compose.loadtest.yml up -d --build
curl -s localhost:8080/loadtest/ping   # == pong (smoke)
k6 run --env RATE=200 --env DURATION=150s k6/steady.js   # 2분+ 지속
sh observe.sh   # ← TIME_WAIT 피크 캡처 (스크린샷)
docker compose -f docker-compose.loadtest.yml down
```

**A-2 (S2, after):**
```bash
NGINX_CONF=./nginx/keepalive.conf TOMCAT_KEEPALIVE_TIMEOUT=80s \
  docker compose -f docker-compose.loadtest.yml up -d --build
k6 run --env RATE=200 --env DURATION=150s k6/steady.js
sh observe.sh   # ← TIME_WAIT 수십, ESTAB 풀 유지 캡처
docker compose -f docker-compose.loadtest.yml down
```

> `observe.sh` 출력에서 nginx/backend 중 **어느 쪽에 TIME_WAIT 이 쌓이는지** 확인 →
> active-closer 확정 (천장 vs 버킷 서사 결정, SoT §12).

## Measurement B — 처리량 천장 (claim: 조건부)

천장을 낮은 RPS 에서 보려면 nginx 컨테이너의 ephemeral 포트 풀을 좁힌다 (shake-table, ADR 명시):

```yaml
# docker-compose.loadtest.yml 의 nginx 서비스에 임시 추가
  nginx:
    sysctls:
      - net.ipv4.ip_local_port_range=40000 41000   # 1,000개 → ~16 RPS 천장
```

```bash
# S0 에서 RATE 를 점증(예: 10→20→40)하며 conn_errors(status 0) 가 치솟는 RPS = 천장
k6 run --env RATE=20 --env DURATION=150s k6/steady.js
# S2 로 바꿔 동일 RATE → conn_errors 0 (천장 소멸) 확인
```

> ⚠️ 천장이 또렷이 안 잡히면(예: backend 가 active-close 라 ephemeral 고갈이 안 일어남)
> 이 수치는 이력서에서 빼고 TIME_WAIT + race 두 수치로 간다 (SoT §10 정직성).

## Measurement C — 502 race before/after (claim: 0.X% → 0%)

**C-1 (S1, race 등장):**
```bash
NGINX_CONF=./nginx/keepalive.conf TOMCAT_KEEPALIVE_TIMEOUT=1s \
  docker compose -f docker-compose.loadtest.yml up -d --build
k6 run --env VUS=30 --env DURATION=180s k6/burst.js   # status_502 카운트
docker compose -f docker-compose.loadtest.yml logs nginx | grep "upstream prematurely closed"
docker compose -f docker-compose.loadtest.yml down
```

**C-2 (S2, race 소멸):**
```bash
NGINX_CONF=./nginx/keepalive.conf TOMCAT_KEEPALIVE_TIMEOUT=80s \
  docker compose -f docker-compose.loadtest.yml up -d --build
k6 run --env VUS=30 --env DURATION=180s k6/burst.js   # status_502 == 0 기대
docker compose -f docker-compose.loadtest.yml down
```

---

## 캡처 → 산출물

- k6 요약(`status_502`, `conn_errors`, http_req_duration), `observe.sh` 출력, nginx error log 를
  스크린샷/텍스트로 [`../docs/research/assets/`](../docs/research/assets/) 에 저장.
- JSON 시계열이 필요하면 `k6 run --out json=out.json ...` 후 플롯.

## 정직성 메모

- backend 안티패턴(S0/S1)은 **loadtest profile + 본 디렉터리 한정** — 운영 배포 안 됨.
- race 측정 시 nginx `proxy_next_upstream off` 로 retry 마스킹 차단 (keepalive.conf 에 반영).
- port range 좁히기는 "측정 가속(shake-table), 기본값에서도 동일 메커니즘"을 ADR 에 명시.
