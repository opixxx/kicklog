# EXEC_PLAN — concurrency-ceiling-harness

| 항목 | 값 |
|---|---|
| Task | concurrency-ceiling-harness |
| Type | chore |
| Branch | chore/concurrency-ceiling-harness |
| Worktree | /Users/opix/Developer/kicklog/.worktrees/concurrency-ceiling-harness |
| Port | 9000 |
| 생성 시각 | 2026-10-30 21:05 |
| 상태 | `active` |
| 개발 방식 | **TDD (Red → Green → Refactor)** |

---

## 1. 목표 (Goal)

외부 의존 지연 하의 **동시성 처리 모델**을 측정으로 선택하기 위한 계측 하네스를 만든다.
현재 백엔드는 동기 블로킹(`spring-boot-starter-webmvc`) + Tomcat 스레드 200 + HikariCP 10 구성이고,
인증 경로가 외부 HTTP(Apple JWKS · Kakao)를 **커넥션 풀 없이**(`SimpleClientHttpRequestFactory`)
호출한다. 이 구조에서 처리량 천장이 어디에, 왜 생기는지를 재현 가능한 측정으로 드러내는 것이 목표다.

본 작업은 **계측 장치까지만** 만든다 — 기술 후보 적용·판정은 측정 결과를 받은 뒤 별도로 결정한다
(설계 문서 §0 "포트폴리오 전용 · 조건부 보류" 전제를 따른다).

핵심 설계 의도: **소프트 천장(스레드 200 · 풀 10)이 하드웨어 천장보다 아래에 오게** 만들어,
CPU 가 여유인데도 처리량이 꺾이는 현상을 분리 관측한다. 그래서 워크로드를 셋으로 **분리**한다 —
섞으면 어느 자원이 구속자인지 귀속할 수 없다.

| 워크로드 | 성격 | 구속 자원 가설 |
|---|---|---|
| W-EXT | 외부 HTTP 바운드 (DB 미접촉) | Tomcat 스레드 200 |
| W-DB | DB 바운드 (외부 미접촉) | HikariCP 10 |
| W-MIX | 혼합 | 둘 중 먼저 포화하는 쪽 |

## 2. 접근 (Approach)

### 2-1. 변경 대상

| 파일 | 변경 |
|---|---|
| `tools/loadtest/mock-upstream.mjs` | **신규** — 지연 주입 가능한 mock 외부 의존 (Node stdlib, 무의존) |
| `backend/.../loadtest/LoadTestExternalController.kt` | **신규** — W-EXT 엔드포인트 |
| `backend/.../loadtest/LoadTestUpstreamClient.kt` | **신규** — 외부 호출 클라이언트 (팩토리 교체 가능) |
| `backend/.../loadtest/LoadTestHttpClientConfig.kt` | **신규** — request factory 를 property 로 선택 |
| `backend/.../loadtest/LoadTestProperties.kt` | **신규** — `kicklog.loadtest.*` 바인딩 |
| `backend/src/main/resources/application-loadtest.yml` | 스레드·풀·가상스레드 노브 + metrics 노출 |
| `infra/terraform-loadtest/k6/w-ext.js` `w-db.js` `w-mix.js` | **신규** — 워크로드 3종 |
| `tools/loadtest/run-measurement.sh` | **신규** — 1회 측정 실행·수집 |

### 2-2. 양보 불가 규칙

1. **격리**: 새 빈 전부 `@Profile("loadtest & !prod")`. 기존 `LoadTestController` 와 동일 기준.
   prod 에서는 라우트 매핑 자체가 없어야 한다(404).
2. **운영 코드 형상 보존**: W-EXT 의 기본 request factory 는 운영 인증 경로와 **같은**
   `SimpleClientHttpRequestFactory` 다. 그래야 "현재 운영 형상의 천장"을 측정한 것이 된다.
   풀링 버전은 `kicklog.loadtest.http-client=pooled` 로 **전환**해 비교한다 — 기본값을 바꾸지 않는다.
3. **운영 코드 미변경**: `config/RestClientConfig.kt` 와 인증 경로는 본 PR 에서 건드리지 않는다.
   개선안 적용은 측정 후 별도 판단.
4. **빌드 toolchain 유지(17)**: `spring.threads.virtual.enabled` 는 **런타임** 체크다.
   17 바이트코드를 JDK 21 런타임으로 실행하면 가상 스레드가 켜진다 → toolchain 변경 불필요.
   따라서 측정은 `bootJar` + JDK 21 `java -jar` 로 한다. (Dockerfile 의 Corretto 17 은 미변경 —
   가상 스레드 "채택" 시의 조건으로 ADR 에 남긴다.)

### 2-3. 계약

```
GET /loadtest/ext?delayMs=200
  → 200 { upstreamDelayMs, upstreamPid, elapsedMs }
  → 502 EXTERNAL_UPSTREAM_UNAVAILABLE (upstream 실패·타임아웃)   # 스택·내부 URL 노출 금지
```

`upstreamPid` 는 mock 워커 식별용이다 — 클러스터로 띄우므로 어느 워커가 응답했는지 보여야
mock 쪽 편중을 발견할 수 있다. 상태코드는 기존 `EXTERNAL_APPLE/KAKAO_UNAVAILABLE` 과 같은
**502 BAD_GATEWAY** 로 맞춘다 (외부 의존 장애의 기존 규약).

```
kicklog.loadtest.upstream-base-url   (기본 http://localhost:9100)
kicklog.loadtest.http-client         simple | pooled   (기본 simple = 운영 형상)
kicklog.loadtest.default-delay-ms / max-delay-ms
kicklog.loadtest.connect-timeout-millis / read-timeout-millis
```

**커넥션 풀 상한 노브는 두지 않는다.** `java.net.http.HttpClient` 는 풀 크기를 빌더로 받지 않고
JVM 전역 시스템 프로퍼티(`jdk.httpclient.connectionPoolSize`)로만 받는다. property 로 선언만 해 두면
"바꿨다고 기록했는데 실제로는 안 바뀐" 측정이 된다. 필요해지면 기동 플래그로 주고 그 사실을 기록한다.

계측 노브 (전부 env, 이미지 재빌드 없이 교체):
`TOMCAT_MAX_THREADS` · `DB_POOL_SIZE` · `VIRTUAL_THREADS` · `LOADTEST_HTTP_CLIENT`

### 2-4. 관측

`management.endpoints.web.exposure.include` 에 `metrics` 추가 +
`server.tomcat.mbeanregistry.enabled=true` → 측정 중 폴링:
`tomcat.threads.busy` · `tomcat.threads.config.max` · `jvm.threads.live` ·
`hikaricp.connections.active` · `hikaricp.connections.pending` · `process.cpu.usage`

## 3. 테스트 케이스 (Test Cases) — TDD 핵심

> 대상은 **loadtest 프로파일 전용 하네스**다. 운영 동작을 바꾸지 않으므로 Cucumber 인수 시나리오는
> 과하다. 계약·격리·팩토리 선택에 **JUnit5 + 실제 stub 서버**(`jdk.httpserver`)로 초점을 맞춘다.

### Happy Path
- [ ] `GET /loadtest/ext?delayMs=50` → 200, `upstreamDelayMs=50`, `elapsedMs >= 50`
- [ ] `delayMs` 미지정 → 기본값(200) 적용
- [ ] `http-client=simple` → `SimpleClientHttpRequestFactory` 빈 주입
- [ ] `http-client=pooled` → `JdkClientHttpRequestFactory` 빈 주입

### Unhappy Path (예외)
- [ ] upstream 이 500 → `EXTERNAL_*` ErrorCode 로 매핑, 스택·내부 URL 미노출
- [ ] upstream 미기동(connection refused) → `EXTERNAL_*`, 무한 대기 없이 타임아웃
- [ ] `delayMs` 음수 → 400 검증 실패 (한글 메시지)

### Edge Cases
- [ ] `prod` 프로파일 활성 시 `/loadtest/ext` 404 (`& !prod` 격리 검증)
- [ ] `delayMs` 상한 초과(> 10000) → 400 (측정 사고 방지)

### 테스트 작성자
백엔드 → `backend-test-writer` agent 위임

## 4. 검증 (Verification)

### 자동 검증
```bash
cd backend && ./gradlew check
```

### 하네스 동작 검증 (수동)
```bash
# 1) mock upstream
node tools/loadtest/mock-upstream.mjs --port 9100 &
curl -s 'http://localhost:9100/delay?ms=100' -w ' %{time_total}\n'   # ≈0.10s

# 2) backend (JDK 21 런타임, 스레드 200)
cd backend && ./gradlew bootJar
TOMCAT_MAX_THREADS=200 java -jar build/libs/*.jar --spring.profiles.active=loadtest &
curl -s 'http://localhost:8080/loadtest/ext?delayMs=200' -w ' %{time_total}\n'
curl -s localhost:8080/actuator/metrics/tomcat.threads.config.max   # == 200

# 3) 가상 스레드 토글이 실제로 먹는지 (JDK 21 런타임 확인)
VIRTUAL_THREADS=true java -jar build/libs/*.jar --spring.profiles.active=loadtest &
# 로그에 가상 스레드 기동 흔적 / jvm.threads.live 가 부하 중 폭증하지 않음
```

### 측정 수용 조건 (하네스가 "쓸 수 있다"의 기준)
- [ ] mock upstream 단독으로 목표 주입률의 **3배** 이상 소화 (mock 이 병목이면 측정 무효)
- [ ] k6 `dropped_iterations` 를 리포트에 분리 기록 (open model 이라 미기록 시 처리량 과대계상)
- [ ] 측정 중 `process.cpu.usage` 수집 — 천장이 CPU 인지 설정인지 귀속하려면 필수

### 커버리지
새 코드 70% 이상

---

## (Optional) 위험도 / 롤백

**Risk = Caution**

- DB 마이그레이션 없음 · API breaking change 없음 · 운영 코드 경로 미변경.
- 유일한 실질 위험은 **인증 우회·지연 주입 엔드포인트의 운영 노출**이다.
  방어는 `@Profile("loadtest & !prod")` 단일 기준이며 테스트로 검증한다(Edge Case 1).
- 롤백: 브랜치 폐기로 충분(운영 설정·스키마 미변경).

## (Optional) 후속 / 관련 이슈

- 측정 실행 및 ADR 작성(후보 ①~④ 판정)은 본 PR 범위 밖 — 하네스 머지 후 진행.
- 선행 개선 후보(본 PR 미포함): 인증 경로 외부 호출 타임아웃 미설정
  (`AppleIdentityVerifier` · `KakaoOAuthClient` 의 `RestClient.create()`), `server.shutdown: graceful` 미설정,
  Apple JWKS 매 로그인 fetch(캐시 없음).
- AWS loadtest 환경(mock upstream 인스턴스 추가·스펙 상향)은 로컬 측정으로 현상 재현 후 판단.

## (Optional) 학습 기록

- Trigger: none (작성 시점)
