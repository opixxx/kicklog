# EXEC_PLAN — keepalive-lifecycle

| 항목 | 값 |
|---|---|
| Task | keepalive-lifecycle |
| Type | refactor |
| Branch | refactor/keepalive-lifecycle |
| Worktree | /Users/opix/Developer/kicklog/.worktrees/keepalive-lifecycle |
| Port | 9000 |
| 생성 시각 | 2026-05-30 11:57 |
| 상태 | `in_progress` |
| 개발 방식 | **실험 기반 검증 (부하 테스트 매트릭스) + 최소 smoke test** |

---

## 1. 목표 (Goal)

경로 B(`nginx → backend` loopback)의 **keep-alive lifecycle**을 통제된 복제 환경에서 재현·측정·예방하기 위한 부하 테스트 하네스를 구축한다. 운영(`docs/research/assets/step0-prod-observation.md`)에서 정성 확인한 upstream keepalive 부재를, 복제 환경에서 ① loopback TIME_WAIT 낭비 → ② keepalive 도입 → ③ idle timeout 비대칭 502 race → ④ 비대칭 원칙 예방의 4막으로 정량화한다. 설계 SoT: `docs/research/keepalive-race-portfolio-scenario.md`.

본 EXEC_PLAN(Step 1) 범위 = **재현 시스템(SUT) 구축**. 측정 실행(Step 2~4)·ADR(Step 6)은 후속.

## 2. 접근 (Approach)

**backend (profile 격리 — 운영 무영향)**
- `loadtest/LoadTestController.kt` — `@Profile("loadtest")` `GET /loadtest/ping → 200 "pong"`. Kakao/DB 미접촉으로 nginx↔backend hop 격리.
- `loadtest/LoadTestSecurityConfig.kt` — `@Profile("loadtest")` + `@Order(HIGHEST_PRECEDENCE)` SecurityFilterChain, `securityMatcher("/loadtest/**")` permitAll. 운영 `SecurityConfig` 미변경.
- `resources/application-loadtest.yml` — `server.tomcat.keep-alive-timeout` 을 `${TOMCAT_KEEPALIVE_TIMEOUT:20s}` 로 토글 가능하게.

**harness (repo 루트 `loadtest/`)**
- `docker-compose.loadtest.yml` — postgres + backend(`SPRING_PROFILES_ACTIVE=loadtest`) + nginx(conf 마운트). host `8080→nginx:80`.
- `nginx/no-keepalive.conf` (S0: upstream keepalive 없음 = 현 운영 모사)
- `nginx/keepalive.conf` (S1/S2: `keepalive 32`+`proxy_http_version 1.1`+`Connection ""`, `keepalive_timeout 60s`)
- `k6/steady.js` (P-steady: TIME_WAIT/천장 측정), `k6/burst.js` (P-burst: race 측정)
- `observe.sh` — `ss` TIME_WAIT 캡처 헬퍼, `README.md` — 3막 실행 절차 + port-range shake-table 안내.

**양보 불가 규칙**
- 운영 `SecurityConfig`·`nginx-kicklog.conf` 미변경 (profile/별도 디렉터리로 완전 격리).
- 안티패턴(S0/S1)은 절대 운영 배포 안 됨 (loadtest profile + loadtest/ 디렉터리 한정).

## 3. 테스트 케이스 (Test Cases)

> 본 작업의 핵심 검증은 **부하 실험 매트릭스**(JUnit 아님). backend 변경은 profile-gated 경량 엔드포인트(≈30줄)라 단위 테스트는 smoke 수준.

### Smoke (backend)
- [ ] `/loadtest/ping` 은 `loadtest` profile 에서 200 "pong" 반환
- [ ] `loadtest` profile 비활성 시 빈 미등록 (운영 무영향) — 수동 확인

### 실험 매트릭스 (Step 2~4, 본 PR 이후 실행)
- [ ] A: S0+P-steady → `ss` TIME_WAIT 수천 (before) / S2 → 수십 (after)
- [ ] B: S0+P-steady ramp → plateau 천장 (조건부) / S2 → 천장 소멸
- [ ] C: S1+P-burst → 502 race 0.X% + `upstream prematurely closed` / S2 → 0%

## 4. 검증 (Verification)

### 자동 검증
- `cd backend && ./gradlew compileKotlin` — 컴파일 게이트
- (smoke) `cd backend && ./gradlew test --tests "*LoadTest*"` (작성 시)

### 시나리오 검증 (Step 1 완료 기준)
- `cd loadtest && NGINX_CONF=./nginx/no-keepalive.conf docker compose -f docker-compose.loadtest.yml up` → `curl localhost:8080/loadtest/ping` == `pong`
- nginx conf 토글(no-keepalive ↔ keepalive)·`TOMCAT_KEEPALIVE_TIMEOUT` env 토글이 동작

---

## (Optional) 위험도 / 롤백
- Risk = **Safe**. profile/디렉터리 격리로 운영 무영향. 롤백 = 파일 삭제.

## (Optional) 후속
- Step 2~4: 실험 실행·캡처 → `docs/research/assets/`
- Step 6: `docs/adr/0010-keepalive-lifecycle.md` 작성
