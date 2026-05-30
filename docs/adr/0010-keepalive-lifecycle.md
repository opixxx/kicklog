# ADR-0010: nginx↔backend Keep-Alive lifecycle — loopback TIME_WAIT 와 idle timeout 비대칭 502 race

- **Status**: Accepted
- **Date**: 2026-05-30
- **선행 ADR**: ADR-0006 (호스팅: nginx-on-box, ALB 없음), ADR-0009 (free-tier, ALB 금지)
- **설계 SoT**: `docs/research/keepalive-race-portfolio-scenario.md`
- **측정 산출물**: `docs/research/assets/{step0-prod-observation,measurement-A-timewait,measurement-C-race}.md`

## Context

KickLog 운영은 **nginx-on-box → Tomcat** 구조다 (ADR-0006 D2 "NAT/ALB 없이 단순 구성", ADR-0009 D3 "ALB 생성 시 감지"). 즉 같은 박스 안 `nginx → 127.0.0.1:8080` loopback 경로가 모든 API 트래픽이 지나는 길목이다.

운영 nginx 설정(`infra/scripts/nginx-kicklog.conf`)을 SSM 으로 점검(Step 0)한 결과 — `location /` 에 **upstream keepalive 가 없다** (`proxy_http_version 1.1`·`keepalive` 풀·`Connection ""` 부재). nginx 동작 정의상 이는 **매 요청마다 nginx↔backend 신규 TCP 커넥션** 을 의미하고, 실측(`ss`)에서도 `:8080` 소켓이 ESTABLISHED 풀 없이 TIME-WAIT 으로 빠지는 게 확인됐다.

이 경로에는 keep-alive 를 켜기 전/후로 **두 본질이 인과로 연결**된다:

```
① keepalive 없음  → 매 요청 loopback 신규 커넥션 (TIME_WAIT 낭비)        ← 현 운영 실재
② keepalive 도입  → 커넥션 재사용 (자원 회수)
③ 그러나 idle timeout 비대칭(backend < proxy) → 간헐 502 race            ← keep-alive 의 함정
④ 비대칭 원칙(backend > proxy)으로 예방
```

전제 — **ALB 도입 금지(ADR-0006/0009 유지)**. 본 ADR 의 프록시는 nginx 다.

## 측정 (Colima Linux VM + docker compose, 복제 환경)

> 운영 박스(free-tier)에 부하 주입 ❌. 운영 *설정을 복제* 한 격리 환경에서 측정하고, 운영 동일 스택임은 Step 0 관찰로 연결. 안티패턴은 `@Profile("loadtest")` + `loadtest/` 디렉터리에 격리 — **운영 배포 안 됨**.

| 측정 | before | after | 비고 |
|---|---|---|---|
| **A. loopback TIME_WAIT** (200 RPS steady) | **~14,700** (nginx 10.6K + backend 7.2K) | **~122**, ESTAB 1개로 3만 요청 reuse | **99%↓** |
| **C. 502 race** (간헐 burst, Tomcat 1s) | **0.05% (1/1,801)** + `upstream prematurely closed` 로그 | **0% (0/1,760)** | 비대칭 해소 |
| latency (p95) | 3.40ms | 3.22ms | **거의 불변** |

- A 의 평형 TIME_WAIT 은 `RPS × TIME_WAIT(60s)` 계산식과 일치.
- C 의 "1000:1~2" 비율은 race window(backend FIN ~ nginx 인지 사이) 의 너비. **steady 고RPS 로는 재현 불가**(커넥션이 안 쉬어 backend idle timeout 미발동) — 반드시 간헐 idle-gap.
- **정직성**: race 관측 가속을 위해 Tomcat `keep-alive-timeout` 을 1s 로 압축(shake-table). **기본 20s 에서도 동일 메커니즘, window 너비만 다름.** "운영 502 사고" 가 아니라 **예측 → 재현 → 예방** (운영엔 keepalive 가 없어 race 가 발생한 적 없음).

## Decisions

### D1. **비대칭 원칙** 을 표준 규칙으로 채택 — "먼저 끊는 쪽은 proxy"

- **선택**: 프록시 앞단에 keep-alive 를 두는 모든 구성에서 `backend keep-alive-timeout > proxy idle timeout` 을 불변식으로 강제. (현 nginx: Tomcat `server.tomcat.keep-alive-timeout` > nginx upstream `keepalive_timeout`)
- **이유**:
  - backend 가 먼저 FIN → proxy 는 죽은 커넥션을 모르고 송신 → RST → 502. backend 가 *나중에* 끊으면 proxy 가 close 를 수신해 다음 요청은 새 커넥션 → race 0.
  - nginx 든 (향후) ALB 든 프록시 종류와 무관한 본질 규칙. SSE/WebSocket 도입 시 더더욱 backend > proxy.
- **기각**: `Connection: close` 강제(keep-alive 포기 → ① 재발), proxy retry 마스킹(근본 해결 아님).

### D2. nginx upstream keepalive 도입은 **선택 적용** (도입 시 D1 동반 필수)

- **현실 직시**: 운영 실 트래픽은 피크 10~15 RPS — loopback TIME_WAIT 평형이 수백 개 수준이라 **현 규모에선 ① 낭비의 실질 임팩트가 작다** (천장 28,232 대비 여유 큼). latency 이득도 loopback 이라 미미(측정상 거의 0).
- **선택**: upstream keepalive 를 *지금 당장 prod 에 강제하지 않는다*. 단 적용한다면 `keepalive 32` + `proxy_http_version 1.1` + `Connection ""` 를 **반드시 D1 비대칭과 함께** (race 예방). 트래픽이 커지거나 외부 프록시(ALB 등) 도입 시 본 ADR 의 검증을 근거로 적용.
- **이유**: 정직성 — 측정으로 메커니즘은 확정했지만 현 규모에선 큰 이득이 아님을 인정. 과적용보다 "함정을 알고 보류" 가 성숙한 선택.

### D3. 재현·측정 방법론 (산출물)

- `loadtest/` 하네스: docker compose(postgres+backend+nginx), nginx conf 2종(no-keepalive/keepalive), k6 2종(steady/burst), `observe.sh`(컨테이너 `/proc/net/tcp` 집계), Grafana 스택(prometheus+grafana+node-exporter).
- backend: `@Profile("loadtest")` 경량 `GET /loadtest/ping` + 전용 SecurityFilterChain — 운영 `SecurityConfig` 무변경, 운영 배포 안 됨.
- 검증 환경: macOS 네이티브는 TIME_WAIT 동작이 Linux 와 달라 부적격 → **Colima Linux VM** 사용.

### D4. 기각/보류

- **Measurement B (처리량 천장)** — 조건부였고 200 RPS 에서 천장(포트 고갈) 미도달. active-closer 가 nginx·backend 혼합이라 ephemeral 고갈이 또렷이 안 잡힘 → **이력서/ADR 수치에서 제외** (TIME_WAIT·race 두 수치로 충분). 필요 시 `ip_local_port_range` 축소로 후속 가능.
- **ALB 도입** — ADR-0006/0009 유지, 미도입.

## Consequences

- **얻는 것**: nginx↔backend keep-alive lifecycle 의 두 함정(TIME_WAIT 낭비·idle timeout race)을 메커니즘·수치로 확정. 비대칭 원칙이 표준 규칙으로 명문화 → 향후 keep-alive/프록시 도입 시 race 사전 예방.
- **Trade-off (D1 적용 시)**: backend idle 커넥션이 더 오래 살아 자원 점유 ↑ (수십 개 vs race 0% — 충분히 감수). 압박 시 `max-keep-alive-requests` 병행.
- **운영 영향**: 현재 0 (D2 로 prod 미적용). 안티패턴은 loadtest 격리.
- **재발 방지**: 측정 중 발견한 함정 2건을 `docs/agent/learning.md` 후보로 — ① zsh 는 unquoted 변수 단어분리 안 함(`docker compose $VAR` malformed), ② node-exporter `network_mode: service:X` 가 컨테이너 netns 를 pin 해 compose 재생성 차단(`docker rm -f` 직접 제거 필요).

## 참조

- RFC 7230 (HTTP/1.1 Connection/Keep-Alive), Nginx `keepalive`/`keepalive_timeout`/`proxy_http_version`, Spring Boot `server.tomcat.keep-alive-timeout`
- 관련: `loadtest/README.md`(3막 실행), `docs/research/loadtest-portfolio-scenario.md`(경로 A: backend→Kakao ephemeral port, 별개 ADR 예정)
