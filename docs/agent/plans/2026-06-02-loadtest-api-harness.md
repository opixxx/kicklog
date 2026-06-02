# EXEC_PLAN — loadtest-api-harness

| 항목 | 값 |
|---|---|
| Task | loadtest-api-harness |
| Type | feature |
| Branch | feature/loadtest-api-harness |
| Worktree | /Users/opix/Developer/kicklog/.worktrees/loadtest-api-harness |
| Port | 9000 |
| 생성 시각 | 2026-06-02 16:07 |
| 상태 | `done` (구현·테스트·리뷰 완료) |
| 개발 방식 | **TDD (Red → Green → Refactor)** |

---

> **범위 한정**: 이 EXEC_PLAN 은 **복제 부하테스트 트랙의 Phase 0 — 백엔드 하네스 코드**만 다룬다.
> 후속 Phase 1~5 (Terraform 복제환경 · 관찰스택 · k6 시나리오 · 튜닝 before/after · destroy) 는 백엔드 소스 변경이 아니므로 본 파이프라인 밖에서 진행한다.

## 1. 목표 (Goal)

복제 부하테스트 환경에서 **실제 비즈니스 API 의 코드/쿼리 성능**을 측정하려면 (1) OAuth 소셜 로그인을 흉내 낼 수 없는 k6 가 보호 엔드포인트를 호출할 인증 수단과, (2) 빈 테이블이면 인덱스·집계 병목이 드러나지 않으므로 현실적 규모의 데이터가 필요하다. 이 둘을 **`loadtest` 프로파일에서만 활성화되는 하네스**로 추가한다. prod 에는 빈 자체가 등록되지 않아 보안 위험이 없다.

## 2. 접근 (Approach)

**패키지**: `com.opixxx.kicklog.loadtest` (기존 `LoadTestController` 확장, 전부 `@Profile("loadtest")`)

**API 엔드포인트 (2개 추가)**
- `GET /loadtest/token?userId={id}` → `JwtTokenProvider.createAccessToken(userId)` 로 access token 직접 발급
  - 응답: `LoadTestTokenResponse(accessToken: String)`
  - OAuth 검증 우회 — `loadtest` 프로파일 한정이므로 prod 미존재(404)
- `POST /loadtest/seed` → 대량 데이터 INSERT
  - 요청: `LoadTestSeedRequest(userCount: Int, matchesPerUser: Int, quartersPerMatch: Int = 4, friendshipsPerUser: Int = 0)` — 전부 `@field:Positive`/`@field:Min` 검증
  - 응답: `LoadTestSeedResponse(usersCreated, matchesCreated, quartersCreated, friendshipsCreated, seededUserIdFrom, seededUserIdTo)`

**서비스**: `LoadTestSeedService` (`@Profile("loadtest")`)
- `JdbcTemplate.batchUpdate` 로 raw INSERT (수십만 행 — JPA 영속성 컨텍스트 오버헤드 회피)
- INSERT 대상: `users` → `matches` → `quarter_workouts` → (옵션) `friendships`
- `matches.result` 는 **`MatchResultType.derive(teamGoals, opponentGoals)` 규칙을 그대로 재현**해 채운다 (Aggregate invariant 와 일관)
- `played_at` 은 과거~현재로 분산 (시즌/월별 집계 쿼리가 의미 있게 동작하도록)

**보안 (양보 불가)**
- 모든 신규 빈은 `@Profile("loadtest")` — prod 프로파일 부팅 시 빈 미등록 → 라우트 자체 없음(404)
- `SecurityConfig` 의 `permitAll` 경로는 `loadtest` 프로파일에서만 `/loadtest/**` 를 추가 허용 (prod 영향 0)

**DTO 흐름**: `Request → (Service) → Response`. Entity 직접 노출 금지.

**외부 의존**: iOS 클라이언트 영향 없음 (loadtest 전용, 본 하네스 대상 아님).

## 3. 테스트 케이스 (Test Cases) — TDD 핵심

> **🔴 RED 먼저, 🟢 GREEN 다음, 🔵 REFACTOR 마지막**

### (3-A) 인수 시나리오 (Gherkin)

```gherkin
@loadtest @smoke
Feature: 부하테스트 하네스 (loadtest 프로파일 전용)

  Scenario: loadtest 토큰으로 보호 엔드포인트 호출 (Happy)
    Given loadtest 프로파일로 부팅된 서버
    And 시드된 사용자 1명 (userId=1)
    When GET /loadtest/token?userId=1 요청
    Then 200 + accessToken 반환
    And 그 accessToken 으로 GET /users/me 호출 시 200

  Scenario: 대량 시드 (Happy)
    Given loadtest 프로파일로 부팅된 서버
    When POST /loadtest/seed { userCount: 5, matchesPerUser: 10, quartersPerMatch: 4 } 요청
    Then 200 + usersCreated=5, matchesCreated=50, quartersCreated=200

  @edge-case
  Scenario: 시드 파라미터 검증 (Unhappy)
    When POST /loadtest/seed { userCount: 0, matchesPerUser: 10 } 요청
    Then 400 + ErrorCode 검증 에러
```

### (3-B) 유스케이스 / 단위·통합 테스트 케이스

#### Happy Path
- [ ] `LoadTestSeedService.seed(...)` — userCount=5·matchesPerUser=10·quartersPerMatch=4 → users 5 / matches 50 / quarter_workouts 200 행 (Testcontainers 실제 PostgreSQL)
- [ ] 시드된 각 `matches.result` == `MatchResultType.derive(teamGoals, opponentGoals)` (invariant 일관성)
- [ ] `GET /loadtest/token?userId=N` 으로 받은 토큰이 `JwtTokenProvider.verifyAccessToken` 통과 + claims.userId == N (통합)

#### Unhappy Path
- [ ] `POST /loadtest/seed` userCount ≤ 0 또는 matchesPerUser < 0 → 400 (Bean Validation)

#### Edge Cases
- [ ] `quartersPerMatch` 기본값(미지정) → 매치당 4쿼터 생성
- [ ] 보안: prod 프로파일에서는 `/loadtest/token`·`/loadtest/seed`·`/loadtest/ping` 라우트 미존재(404) — 프로파일 격리 회귀 방지 (`@ActiveProfiles("prod")` 슬라이스 또는 빈 부재 검증)

### 테스트 작성자 (자동 위임)
- 백엔드 → `backend-test-writer` agent (Cucumber + Testcontainers + JUnit5 + AssertJ)

## 4. 검증 (Verification)

### 자동 검증
- 백엔드: `cd backend && ./gradlew check`
- 컴파일 게이트: `cd backend && ./gradlew compileKotlin`

### 시나리오 검증 (수동 — loadtest 프로파일 부팅)
```bash
SPRING_PROFILES_ACTIVE=loadtest ./gradlew bootRun   # (postgres 필요)
curl -X POST localhost:8080/loadtest/seed -H 'Content-Type: application/json' \
  -d '{"userCount":5,"matchesPerUser":10}'          # → usersCreated/matchesCreated 확인
curl 'localhost:8080/loadtest/token?userId=1'        # → accessToken 확인
curl localhost:8080/users/me -H "Authorization: Bearer <accessToken>"  # → 200
```
- prod 프로파일 부팅 시 `/loadtest/*` 가 404 인지 확인 (보안)

### 커버리지
- 새 코드 커버리지 70% 이상

---

## (Optional) 위험도 / 롤백

- **Risk = Caution** — 인증 우회 토큰 발급은 보안 경계이나, **`@Profile("loadtest")` 격리**로 prod 무영향이 핵심 안전장치. DB 스키마 변경 없음(런타임 INSERT).
- 롤백: 신규 `loadtest` 빈/엔드포인트 제거. DB 영향은 복제환경 한정이며 `terraform destroy` 로 환경째 소멸.

## (Optional) 후속 / 관련 이슈

- **Phase 1~5** (본 PR 밖): Terraform 복제환경(EC2 t3.large + RDS db.t3.medium + 부하생성 EC2, state 격리) → 관찰스택(Grafana/Prometheus + node/postgres exporter, RDS Performance Insights) → k6 시나리오(read/write/mixed, ramping arrival rate) → 병목 분석·튜닝 before/after → destroy
- **튜닝 시 Flyway 인덱스 마이그레이션**은 별도 작업 + 사용자 확인 (DB 마이그레이션은 에스컬레이션 대상)
- 결과는 **ADR-0011 (API 성능 부하테스트 / 복제환경)** 으로 기록 — 이력서 트랙 (경로 A 후보를 이걸로 채움)

## (Optional) 학습 기록

- Trigger: review-major + self-heal
- Root cause:
  - (1) 테스트가 `com.fasterxml.jackson...ObjectMapper`(Jackson 2)를 `@Autowired` → Spring Boot 4 의 DI 빈은 `tools.jackson...ObjectMapper`(Jackson 3) 라 NoSuchBeanDefinitionException. RED→GREEN 전환 시 발견.
  - (2) code-review Major: PK 회수("max(id) 이후 행")의 동시성 가정 → `pg_advisory_xact_lock`(트랜잭션 스코프)로 직렬화.
  - (3) 로컬 Testcontainers 가 colima 소켓 미인식 → 전 테스트 skip(통과로 오인 위험). env 오버라이드로 해결.
- Prevention: 위 3건을 memory(project-loadtest-portfolio-progress 함정 ③④) 및 backend-test-writer agent-memory 에 반영.
- Promoted to: memory | backend-test-writer agent-memory

---

> 완료 시: `상태` 필드를 `done`으로 변경하고 PR 본문에 본 파일 링크 첨부.
