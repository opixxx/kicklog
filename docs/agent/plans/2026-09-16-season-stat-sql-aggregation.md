# EXEC_PLAN — season-stat-sql-aggregation

| 항목 | 값 |
|---|---|
| Task | season-stat-sql-aggregation |
| Type | refactor |
| Branch | refactor/season-stat-sql-aggregation |
| Port | 9000 |
| 생성 시각 | 2026-09-16 |
| 상태 | `done` |
| 개발 방식 | **특성화 테스트 우선 리팩토링** (동작 보존이 최우선) |

---

## 1. 목표 (Goal)

시즌 통계 집계를 **애플리케이션 메모리 집계 → DB 집계 SQL** 로 전환한다.

현재 `SeasonStatService.calculate()` 는 1년치 `Match` 전체를 쿼터까지 fetch join 으로
JVM 에 올린 뒤 Kotlin 에서 `sumOf`/`count`/`flatMap` 으로 합산한다. 경기 N 개면
**엔티티 N + 4N 개**가 heap 에 생성된다. 2026-09-06 장애 대응으로 heap 을 642MB → 224MB
로 줄였기 때문에(ADR 후속) 이 방식의 여유가 이전의 1/3 이 됐고, 친구 통계까지 조회하면
같은 부하가 배수로 붙는다.

DB 가 훨씬 잘하는 일(대량 행 합산)을 DB 에 맡겨 **전송 행 수를 N+4N → 1+1+≤12 로,
엔티티 생성을 거의 0 으로** 줄인다.

> **성능 수치 확보는 본 PR 범위 밖이다.** 본 PR 의 목표는 "**값이 완전히 동일한** 대체 구현"
> 이며, JFR 할당률 baseline·A/B 부하 측정은 후속 단계다 (5장).

## 2. 접근 (Approach)

### 2.1 인터페이스 — `MatchStore` 에 집계 3종 추가

```kotlin
// match/repository/SeasonAggregates.kt (신규)
data class SeasonMatchAggregate(
    val totalDistanceM: Int, val totalGoals: Int, val totalAssists: Int,
    val matchCount: Int, val winCount: Int, val drawCount: Int, val lossCount: Int,
    val maxSpeedKmh: Double, val longestMatchDistanceM: Int, val mostSprintCount: Int,
)
data class SeasonQuarterAggregate(
    val quarterCount: Int,
    val weightedHeartRateSum: Long,   // SUM(avgHeartRate * durationSeconds)
    val totalDurationSeconds: Long,   // SUM(durationSeconds)
)
data class MonthlyDistance(val month: Int, val distanceM: Int)   // month: 1~12 (UTC)

interface MatchStore {
    fun aggregateSeasonMatches(userId: Long, start: Instant, end: Instant): SeasonMatchAggregate
    fun aggregateSeasonQuarters(userId: Long, start: Instant, end: Instant): SeasonQuarterAggregate
    fun aggregateMonthlyDistance(userId: Long, start: Instant, end: Instant): List<MonthlyDistance>
}
```

**나눗셈은 Service 에서 한다.** `avgHeartRate = if (totalDuration == 0L) 0 else
(weightedSum / totalDuration).toInt()` — SQL 에서 나누면 0 division 과 정수 버림을
둘 다 SQL 로 처리해야 해 오히려 복잡하고, 기존 Kotlin 구현과 반올림이 어긋날 위험이 있다.

### 2.2 두 구현

| 구현 | 방식 | 역할 |
|---|---|---|
| `InMemoryMatchRepository` | 현재 `calculate()` 로직을 그대로 이식 | **참조 구현** — 기존 단위 테스트 6개가 그대로 통과해야 한다 |
| `JpaMatchStore` | 집계 SQL (native) | 실제 운영 경로 — Testcontainers 로 별도 검증 |

`SeasonStatServiceTest` 는 완전 인메모리(Spring 컨텍스트·DB 없음)라 SQL 을 검증하지 못한다.
따라서 **SQL 구현 검증은 Testcontainers 통합 테스트로 분리**한다.

### 2.3 집계 SQL — fan-out 회피가 핵심

`matches` 와 `quarter_workouts` 를 **조인해서 한 번에 집계하면 안 된다.** 경기 1행이
쿼터 수만큼 복제되어 `SUM(m.total_distance_m)` 이 쿼터 개수배로 중복 합산된다.
→ **집계 단위별로 쿼리를 분리**한다.

```sql
-- ① 경기 단위 (matches 단독)
SELECT COALESCE(SUM(m.total_distance_m),0), COALESCE(SUM(m.goals),0), ...,
       COUNT(*) FILTER (WHERE m.result = 'WIN')  AS win_count, ...,
       COALESCE(MAX(m.max_speed_kmh),0), COALESCE(MAX(m.total_distance_m),0),
       COALESCE(MAX(m.sprint_count),0)
FROM matches m
WHERE m.user_id = :userId AND m.played_at >= :start AND m.played_at < :end;

-- ② 쿼터 단위 (조인은 기간 필터 용도 — 집계 대상이 쿼터 하나라 fan-out 없음)
SELECT COUNT(*), COALESCE(SUM(q.avg_heart_rate::bigint * q.duration_seconds),0),
       COALESCE(SUM(q.duration_seconds),0)
FROM quarter_workouts q JOIN matches m ON m.id = q.match_id
WHERE m.user_id = :userId AND m.played_at >= :start AND m.played_at < :end;

-- ③ 월별 (UTC 고정 필수)
SELECT EXTRACT(MONTH FROM m.played_at AT TIME ZONE 'UTC')::int AS month,
       COALESCE(SUM(m.total_distance_m),0) AS distance_m
FROM matches m
WHERE m.user_id = :userId AND m.played_at >= :start AND m.played_at < :end
GROUP BY 1 ORDER BY 1;
```

**양보 불가 규칙**
- `AT TIME ZONE 'UTC'` 누락 금지 — 현재 구현이 `playedAt.atZone(ZoneOffset.UTC).monthValue`
  이고 api-spec §8.1 에도 "UTC `playedAt.month` 기준" 으로 명시돼 있다. 빠뜨리면 서버 TZ 에 따라
  경기가 다른 달로 집계된다.
- `COALESCE` 필수 — 0건이면 `SUM` 이 NULL 이라 Kotlin `Int` 매핑에서 터진다.
- `::bigint` 캐스팅 — 심박 가중합 오버플로 방지 (현재 구현도 `toLong()` 사용).
- 월별 결과는 **데이터 있는 달만** 반환 → Service 가 12칸 배열로 채운다 (빈 월 0).
- **인수 테스트는 H2(MODE=PostgreSQL) 에서 돈다.** `COUNT(*) FILTER`·`EXTRACT(... AT TIME ZONE)`·
  `::bigint`·`COALESCE(SUM/MAX)` 가 H2 2.4.240 에서 동작함을 사전 확인했다 (backend-test-writer).
- 인덱스는 **`idx_matches_user_played_at_id (user_id, played_at DESC, id DESC)`** (V5) 를 쓴다.
  V7 의 `idx_matches_user_played_at` 은 중복이라 **V15 에서 DROP 됐다.** 세 쿼리의 WHERE 는
  `(user_id, played_at)` 접두사라 이 복합 인덱스로 커버된다. **마이그레이션 없음.**

### 2.4 제거 대상

`findAllByUserIdAndPlayedAtBetween` 은 전환 후 `main` 에서 사용처가 사라진다.
Dead Code 규약에 따라 **인터페이스·두 구현·전용 fetch join 통합 테스트까지 함께 제거**한다.

> A/B 부하 비교는 **브랜치 분리 방식**으로 한다 (사용자 확정). 런타임 스위치를 두지 않으므로
> prod 코드에 죽은 분기가 남지 않는다. 측정 시 이 커밋과 직전 커밋을 각각 배포한다.

## 3. 테스트 케이스 (Test Cases) — ATDD

> 본 작업은 **동작 보존 리팩토링**이다. 기존 테스트(인수 5 + 단위 7 = 12개)는 안전망으로 유지하되,
> **현재 테스트가 못 잡는 함정**을 특성화 테스트로 먼저 덮는다.
> 이 테스트들은 참조 구현(InMemory)에서 GREEN 이어야 하고, SQL 구현에서도 GREEN 이어야 한다.

### (3-A) 인수 시나리오 (Gherkin)

```gherkin
@stat @season
Feature: 시즌 통계 집계

  @smoke
  Scenario: 쿼터가 여러 개인 경기들의 시즌 통계 (Happy — fan-out 회귀 방지)
    Given 사용자에게 2026년 경기 2건이 있고 각 경기에 쿼터가 3개씩 있다
      And 경기별 이동거리는 5000m, 7000m 이다
    When GET /users/me/seasons/2026 을 호출하면
    Then 200 이고 totalDistanceM 은 12000 이다      # 36000 (3배) 이 아니어야 한다
      And matchCount 는 2, quarterCount 는 6 이다

  @edge-case
  Scenario: UTC 기준 12월 말 경기는 12월에 집계된다 (Happy — 월 경계)
    Given 사용자에게 2026-12-31T15:00:00Z 경기가 있다    # KST 로는 2027-01-01
    When GET /users/me/seasons/2026 을 호출하면
    Then monthlyDistanceM 의 12월 칸에 집계된다
      And 2027년 통계에는 포함되지 않는다

  @edge-case
  Scenario: 친구가 아니면 시즌 통계를 조회할 수 없다 (Unhappy — 회귀 방지)
    Given 사용자 A 와 B 가 친구가 아니다
    When A 가 GET /users/{B}/seasons/2026 을 호출하면
    Then 403 FRIEND_UNAUTHORIZED 이다
```

### (3-B) 유스케이스 / 단위·통합 테스트 케이스

**B-1. 기존 단위 테스트 7개 (`SeasonStatServiceTest`) — 수정 없이 통과해야 한다**
참조 구현(InMemory)의 동작 보존 증명. 하나라도 손대면 리팩토링이 아니라 동작 변경이다.

**B-2. 신규 — 참조 구현 특성화 테스트 (인메모리, 빠름)**
- [ ] `경기당 쿼터가 여러 개여도 거리·골·어시스트가 중복 합산되지 않는다` (Happy)
- [ ] `쿼터 durationSeconds 합이 0 이면 avgHeartRate 는 0 이다` (Unhappy — 0 division)
- [ ] `쿼터가 없는 경기도 경기 지표는 집계되고 quarterCount 는 0 이다` (Edge)
- [ ] `UTC 12/31 23:00 경기는 해당 연도 12월에 집계된다` (Edge — 월 경계)
- [ ] `가중평균 심박은 소수점을 버린다` (Edge — 반올림 계약)

**B-3. 신규 — SQL 구현 통합 테스트 (`@SpringBootTest` + Testcontainers) ★ 본 작업의 핵심**
- [ ] `aggregateSeasonMatches 는 쿼터 수와 무관하게 경기 지표를 1회만 합산한다` (Happy — **fan-out**)
- [ ] `aggregateSeasonQuarters 는 기간 내 쿼터만 센다` (Happy)
- [ ] `aggregateMonthlyDistance 는 UTC 월 기준으로 그룹핑한다` (Edge — `AT TIME ZONE` 검증)
- [ ] `경기 0건이면 모든 집계가 0 을 반환한다 (NULL 아님)` (Unhappy — **COALESCE**)
- [ ] `다른 사용자의 경기는 집계에 포함되지 않는다` (Unhappy — 격리)
- [ ] `기간 경계는 start 포함 / end 미포함이다` (Edge)

**B-4. 신규 — 두 구현 동등성 테스트 ★ 값 보존의 최종 관문**
- [ ] `동일 데이터에 대해 InMemory 구현과 Jpa 구현이 같은 SeasonStat 을 반환한다`
  (Testcontainers. 쿼터 복수·빈 쿼터·월 경계·0 duration 을 한 fixture 에 섞어 구성)

### 테스트 작성자 (자동 위임)
`backend-test-writer` agent — Cucumber Feature + Testcontainers 통합 + JUnit5 단위.

## 4. 검증 (Verification)

### 자동 검증
```bash
cd backend
./gradlew compileKotlin
DOCKER_HOST=unix:///Users/opix/.colima/default/docker.sock \
TESTCONTAINERS_DOCKER_SOCKET_OVERRIDE=/var/run/docker.sock \
  ./gradlew test        # learning.md 2026-06-10 — Colima 환경 env 필수
./gradlew check
```

**skipped 카운트 0 확인 필수.** Colima 환경에서 Testcontainers 가 `disabledWithoutDocker`
로 **조용히 skip** 되는 함정이 있다 (learning.md 2026-06-10). "BUILD SUCCESSFUL" 만 보고
통과로 판단하지 않는다 — 본 작업은 통합 테스트가 핵심이라 skip 되면 검증이 전부 무의미해진다.

### 완료 조건
- [x] 기존 테스트 12개(인수 5 + 단위 7) **수정 없이** 통과
- [x] 신규 테스트 전부 통과 — 전체 **248 tests / skipped 0 / failures 0 / errors 0**
- [x] `findAllByUserIdAndPlayedAtBetween` 및 전용 테스트 제거, 컴파일 통과
- [x] `EXPLAIN (ANALYZE, BUFFERS)` — 3개 쿼리 모두 `idx_matches_user_played_at_id` 사용 확인. **DB 실행 시간은 기존과 사실상 동일**(12.696ms → 12.093ms)하고 버퍼는 증가(2,425 → 3,024). 판단 근거는 할당 측정에서 나왔다 — ADR-0014

## 5. 후속 (본 PR 범위 밖)

1. ~~JFR 할당률 baseline 측정~~ → **완료.** JFR 대신 `ThreadMXBean.getThreadAllocatedBytes`
   로 직접 측정. 호출당 할당 **2,726.2KB → 116.6KB (23.4배↓)**, GC **47회 → 1회**,
   호출당 시간 8.186ms → 4.115ms. 하네스는 `SeasonStatAllocationBenchmark`(@Disabled, 수동 실행).
2. **A/B 부하 측정** (ADR-0011 iteration 2) — HikariCP 풀 상향 + non-burstable 인스턴스로
   천장 제거 후, `matchesPerUser` 를 50/200/500 으로 올리며 기울기 비교.
3. ~~결과에 따라 ADR 작성~~ → **완료. ADR-0014.** ADR-0003 D9.1 의 "SQL derive" 문언과
   구현이 어긋나 있었다는 사실도 함께 기록하고, ADR-0003 에 상호 참조를 남겼다.

## 6. 위험도 / 롤백

**Risk: Caution** — 사용자에게 보이는 숫자가 바뀌면 안 되는 작업이다.

- 최대 위험은 **조용한 값 오류**(fan-out 중복 합산, 월 경계 어긋남). 컴파일·기존 테스트는
  통과하는데 숫자만 틀릴 수 있다 → B-3·B-4 가 그 방어선이다.
- DB 마이그레이션 없음 / API 계약 불변 / 인덱스 추가 없음.
- 롤백: 단일 커밋이라 revert 로 즉시 복원.
