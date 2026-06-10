# EXEC_PLAN — audit-fixes

| 항목 | 값 |
|---|---|
| Task | audit-fixes |
| Type | refactor |
| Branch | refactor/audit-fixes |
| Worktree | /Users/opix/Developer/kicklog/.worktrees/audit-fixes |
| Port | 9000 |
| 생성 시각 | 2026-06-10 14:33 |
| 상태 | `done` |
| 개발 방식 | **TDD (Red → Green → Refactor)** |

---

## 1. 목표 (Goal)

2026-06-10 전체 진단 보고서(`docs/agent/reports/2026-06-10-refactoring-audit.html`)의 백엔드 P1~P3 를 해소한다.
P1(DB 성능)은 ADR-0011 부하테스트 2차 측정의 전제 조건 — N+1 제거·중복 인덱스 정리·커넥션 풀 환경변수화로
측정된 병목(seasons p95 2.65s, 커넥션 10 고정)을 제거한다. P2 는 운영 데이터 위생(RefreshToken 누적)과
api-spec 계약(traceId) 충족, P3 는 안전성 소규모 정리다.

## 2. 접근 (Approach)

### P1-1. Match.quarters N+1 제거
- `MatchRepository.findAllByUserIdAndPlayedAtBetween` → `JOIN FETCH m.quarters` 추가 (시즌 집계 전용, 페이지네이션 없음 → 안전).
- 목록(페이지네이션) 쿼리 2개(`findFirstPageByUserId`, `findAllByUserIdAfterCursor`)는 컬렉션 fetch join 시 Hibernate 메모리 페이징 발생 →
  **2단계 로딩**: 기존 쿼리는 그대로 두고, `@Query("SELECT DISTINCT m FROM Match m LEFT JOIN FETCH m.quarters WHERE m.id IN :ids ORDER BY m.playedAt DESC, m.id DESC") fun findAllWithQuartersByIdIn(ids: List<Long>): List<Match>` 추가.
  `MatchService` 목록 경로에서 id 페이징 → fetch join 재조회로 변경, `initialize()` 제거.
- `SeasonStatService.findSeasonMatches` 의 `.onEach { it.quarters.size }` 제거 (fetch join 으로 대체).
- 단건 조회(`findByUserIdAndClientMatchId` 등) 경로는 `@EntityGraph(attributePaths = ["quarters"])` 또는 동일 fetch join 으로 처리.

### P1-2. V15 중복 인덱스 제거
- `V15__drop_redundant_match_index.sql`: `DROP INDEX IF EXISTS idx_matches_user_played_at;` (V7 인덱스 — V5 `idx_matches_user_played_at_id` 의 접두사).

### P1-3. HikariCP 풀 환경변수화 + hibernate 안전망
- `application.yml`: `spring.datasource.hikari.maximum-pool-size: ${DB_POOL_SIZE:10}` (기본 10 유지 — 운영 변경은 인프라에서 결정).
- `hibernate.default_batch_fetch_size: 100` 추가 (잔여 lazy 경로 N+1 안전망).

### P2-1. RefreshToken 만료 정리 스케줄러
- `auth/scheduler/RefreshTokenPurgeScheduler.kt` 신설: `@Scheduled(cron = "0 30 4 * * *")` (UserPurgeScheduler 와 30분 간격).
- `RefreshTokenRepository` 에 `@Modifying @Query("delete from RefreshToken r where r.expiresAt < :now") fun deleteAllExpiredBefore(now: Instant): Int` 추가 (`RefreshTokenStore` 인터페이스 경유).
- 만료 기준: `expiresAt < now` — revoked 여부 무관 (만료 JWT 는 verify 단계에서 거부되어 재사용 탐지에 불필요).
- `@EnableScheduling` 은 기존 설정 재사용 (UserPurgeScheduler 가 이미 동작 중인지 확인).

### P2-2. 에러 응답 traceId (api-spec 계약)
- `common/logging/TraceIdFilter.kt` 신설: `OncePerRequestFilter`, 요청마다 8자 hex traceId 생성 → MDC `traceId` 저장, 응답 후 제거.
- `ErrorResponse` 에 `traceId: String?` 필드 추가, `GlobalExceptionHandler` 가 MDC 에서 읽어 채움.
- `application.yml` 로그 패턴에 `[%X{traceId}]` 포함 (콘솔 패턴).
- 기존 `path` 필드는 유지 (iOS 영향 없음 — 필드 추가만).

### P3. 클린 코드 6건
- `UserController.me()` → `UserService.getMe(userId): UserResponse` 위임 (기존 `requireActiveUser` 재사용).
- `JwtTokenProvider.verify()` unchecked cast → safe cast(`as?`) + `AUTH_INVALID_TOKEN`.
- `AuthService.saveUserWithUniqueDisplayName` 충돌 시 `log.warn` 추가.
- `FriendshipService.runInTransaction` → `transactionTemplate` null 이면 `IllegalStateException` (침묵 무트랜잭션 분기 제거). 생성자 기본값 null 은 단위 테스트 호환 위해 유지하되 트랜잭션 필요 경로에서 명시 실패.
- `VenueService.updateVenue` 중복 조회 정리 (이름 동일 시 중복 검사 스킵).
- `MatchService.initialize()` / `SeasonStatService.onEach` 제거는 P1-1 에 포함.

### 양보 불가 규칙
- API 응답 스키마는 **필드 추가만** (breaking change 금지 — iOS 호환).
- 트랜잭션 경계 기존 유지, 스케줄러 삭제는 벌크 쿼리 1방.
- 마이그레이션은 인덱스 DROP 만 (데이터 변경 없음).

## 3. 테스트 케이스 (Test Cases) — TDD 핵심

> **🔴 RED 먼저, 🟢 GREEN 다음, 🔵 REFACTOR 마지막**

### (3-A) 인수 시나리오 (Gherkin)

```gherkin
@stat @perf
Feature: 시즌 통계 집계 쿼리 효율
  Scenario: 시즌 통계 조회가 쿼터 데이터를 포함해 정확히 집계된다 (Happy)
    Given 사용자에게 2026년 경기 3건 (각 쿼터 2개, 거리 1000m씩) 이 저장돼 있다
    When GET /users/me/seasons/2026 을 호출한다
    Then 200 과 totalDistanceM 합계가 6000 으로 응답한다

@match
Feature: 경기 목록 커서 페이지네이션 (fetch 전략 변경 후 회귀)
  Scenario: 첫 페이지 + 다음 커서 (Happy)
    Given 사용자에게 경기 25건이 저장돼 있다
    When GET /matches?limit=20 을 호출한다
    Then 200 과 items 20건, nextCursor 가 응답되고 각 item 의 quarterCount 가 정확하다
  @edge-case
  Scenario: 커서 이후 페이지 (Edge)
    When 첫 페이지의 nextCursor 로 GET /matches 를 재호출한다
    Then 나머지 5건이 응답되고 hasNext 가 false 다

@auth
Feature: 만료 RefreshToken 정리
  Scenario: 만료 토큰만 삭제된다 (Happy)
    Given 만료된 refresh token 2건과 유효한 refresh token 1건이 저장돼 있다
    When RefreshTokenPurgeScheduler.purgeExpiredTokens() 가 실행된다
    Then 만료 2건은 삭제되고 유효 1건은 남는다
  @edge-case
  Scenario: revoked 됐지만 미만료인 토큰은 보존된다 (Unhappy — 재사용 탐지 보존)
    Given revoked 이지만 만료 전인 refresh token 1건이 저장돼 있다
    When purge 가 실행된다
    Then 해당 토큰은 삭제되지 않는다

@common
Feature: 에러 응답 traceId
  Scenario: 에러 응답에 traceId 가 포함된다 (Happy)
    Given 인증된 사용자
    When 존재하지 않는 리소스를 조회해 404 를 받는다
    Then 응답 body 에 8자 hex traceId 가 포함된다
```

### (3-B) 유스케이스 / 단위 테스트 케이스

#### Happy Path
- [ ] `MatchRepository.findAllByUserIdAndPlayedAtBetween` — fetch join 후 quarters 접근 시 추가 쿼리 0 (Testcontainers, Hibernate statistics 또는 트랜잭션 밖 접근으로 검증)
- [ ] `MatchService.listMatchesByUser` — 2단계 로딩 후에도 정렬(playedAt DESC, id DESC)·커서·quarters 정합 (통합)
- [ ] `RefreshTokenStore.deleteAllExpiredBefore(now)` — 만료 2건 삭제, 유효 1건 보존, 반환값 2 (Testcontainers)
- [ ] `GlobalExceptionHandler` — MDC 에 traceId 있으면 ErrorResponse.traceId 채움 (단위)
- [ ] `UserService.getMe(userId)` — 활성 사용자 UserResponse 반환 (통합)

#### Unhappy Path (예외)
- [ ] `JwtTokenProvider.verify` — payload sub 가 비숫자/누락 시 `AUTH_INVALID_TOKEN` (ClassCastException 누출 금지) (단위)
- [ ] `UserService.getMe` — 삭제된 사용자 → `USER_DELETED` (통합)
- [ ] `FriendshipService.request` — transactionTemplate 미주입 시 명시적 IllegalStateException (단위)
- [ ] `TraceIdFilter` — 응답 완료 후 MDC 에 traceId 잔류하지 않음 (단위)

#### Edge Cases
- [ ] purge 경계값 — `expiresAt == now` 토큰은 삭제되지 않음 (`<` 기준) (Testcontainers)
- [ ] `MatchService` 목록 — 경기 0건 사용자 → 빈 목록 + nextCursor null (회귀, 통합)
- [ ] `VenueService.updateVenue` — 동일 이름으로 업데이트 시 VENUE_NAME_DUPLICATE 미발생 (회귀, 통합)
- [ ] `AuthService.saveUserWithUniqueDisplayName` — 충돌 시 suffix 재시도 동작 회귀 (기존 테스트 유지 확인)

### 테스트 작성자 (자동 위임)
- 백엔드 → `backend-test-writer` agent (Cucumber + Testcontainers + JUnit5 + AssertJ)

## 4. 검증 (Verification)

### 자동 검증
```bash
cd /Users/opix/Developer/kicklog/.worktrees/audit-fixes/backend && ./gradlew compileKotlin   # 빠른 게이트
cd /Users/opix/Developer/kicklog/.worktrees/audit-fixes/backend && ./gradlew check           # 전체 (Testcontainers 포함)
```

### 시나리오 검증 (수동)
- Flyway V15 적용 후 `\di matches*` 에 `idx_matches_user_played_at` 부재, `idx_matches_user_played_at_id` 존재
- `hibernate SQL DEBUG` 로 GET /users/me/seasons/{year} 가 match+quarters 를 1~2 쿼리로 로드
- 에러 응답 예: `{"code":"MATCH_NOT_FOUND","message":"...","path":"/matches/999","traceId":"a1b2c3d4"}`

### 커버리지
- 새 코드 커버리지 70% 이상 (전체 평균)

---

## (Optional) 위험도 / 롤백

- Risk = **Caution**
- V15 는 인덱스 DROP 만 — 롤백 SQL: `CREATE INDEX idx_matches_user_played_at ON matches(user_id, played_at);`
- fetch 전략 변경은 응답 스키마 불변 — 회귀는 기존 인수 테스트로 검출
- traceId 는 필드 추가만 (iOS `APIErrorBody` 가 이미 `traceId?` 디코딩 — breaking 아님)

## (Optional) 후속 / 관련 이슈

- 부하테스트 2차 (ADR-0011 후속): 본 PR 머지 후 `DB_POOL_SIZE=30` + c5 인스턴스로 재측정
- CLAUDE.md "Access 1h + Refresh 90d" vs yml 기본값(15m/30d) 불일치 — 운영 SSM 확인 후 별도 docs 수정
- iOS 동기 수정 불필요 (필드 추가만)
- **[리뷰 M1 결정]** 인증 실패(401/403)는 `HttpStatusEntryPoint` 가 body 를 생성하지 않으므로 traceId 는 **로그로만** 추적된다 (응답 body 의 traceId 는 도메인 예외 4xx/5xx 한정). 일관된 에러 body 가 필요해지면 별도 `AuthenticationEntryPoint` 구현을 후속 작업으로.
- **[리뷰 m4 후속 후보]** 단건 조회 경로의 `withQuarters` 재조회를 `@EntityGraph` 단건 메서드로 대체하면 쿼리 1회 절감 가능.
- **[리뷰 범위 밖]** `JwtAuthenticationFilter.shouldNotFilter` 의 raw literal 경로 비교 — 별도 이슈.

## (Optional) 학습 기록

- Trigger: **production-risk** (Testcontainers 침묵 skip)
- Root cause: Colima 환경에서 plain `./gradlew test` 실행 시 `disabledWithoutDocker` 가 컨테이너 테스트를 **조용히 skip** — "테스트 통과" 가 실DB 검증 없이 보일 수 있음.
- Prevention: 컨테이너 테스트 실행 시 `DOCKER_HOST=unix:///Users/opix/.colima/default/docker.sock TESTCONTAINERS_DOCKER_SOCKET_OVERRIDE=/var/run/docker.sock` 환경변수 필요. 검증 단계에서 skipped 카운트 0 확인 습관화.
- Promoted to: docs/agent/learning.md

### Phase 4 리뷰 결과 (code-reviewer, Opus)
- Critical 0 / Major 2 / Minor 4 → **Comment (머지 가능)**
- M1: 401 body traceId 부재 → 위 "후속" 에 의도 문서화로 처리
- M2: V15 DROP INDEX 락 → 마이그레이션에 락 특성 주석 추가, 트래픽 적은 시간대 적용 권장
- m1: `as T` unchecked cast → `@Suppress` + 의도 주석 반영
- m2(이중 @Transactional)·m4(단건 withQuarters 추가 쿼리)는 의도적 트레이드오프로 수용

---

## TDD 작업 흐름

```
1. 위의 "3. 테스트 케이스" 섹션 채우기 (완료)
2. 🔴 RED: backend-test-writer agent 가 케이스를 코드로 변환 → ./gradlew test 실패 확인
3. 🟢 GREEN: 한 케이스씩 최소 구현 → 테스트 통과
4. 🔵 REFACTOR: 중복 제거, 메서드 분리, 네이밍 정리 → 테스트 여전히 통과
5. 모든 케이스 통과 → "4. 검증" 섹션의 명령 실행
6. self-heal/Critical/누락 테스트가 있었으면 학습 기록 판단
7. PR 생성 (/pr-guide)
```

> 완료 시: `상태` 필드를 `done`으로 변경하고 PR 본문에 본 파일 링크 첨부.
