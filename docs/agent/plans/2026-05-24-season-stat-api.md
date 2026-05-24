# EXEC_PLAN — season-stat-api

| 항목 | 값 |
|---|---|
| Task | season-stat-api |
| Type | feature |
| Branch | feature/season-stat-api |
| Worktree | /Users/opix/Developer/kicklog/.worktrees/season-stat-api |
| Port | 9000 |
| 생성 시각 | 2026-05-24 14:21 |
| 상태 | `done` |
| 개발 방식 | **TDD (Red → Green → Refactor)** |

---

> **단순화 + TDD 원칙**:
> - 본 템플릿은 GearShow의 8섹션을 KickLog용 **4섹션 + optional**로 축소 (Ralph: "계획은 일회용·짧게")
> - **테스트 케이스 섹션**을 통해 TDD 강제 — 구현 전에 테스트 케이스 명시
> - 30줄 미만의 작은 변경은 EXEC_PLAN 자체가 면제됨 (`enforce-plan.sh`)

## 1. 목표 (Goal)

iOS가 라벨링 완료 시 계산한 경기/쿼터별 HealthKit 집계 지표를 서버에 저장하고, 이를 기반으로 연도별 시즌 통계 API를 제공한다. 내 시즌 탭과 친구 탭의 시즌 카드가 같은 계약을 사용할 수 있게 하며, 친구 통계 조회는 `FriendshipAuthorizer`를 재사용해 IDOR를 막는다.

## 2. 접근 (Approach)

- DB: `V7__match_metrics.sql`
  - `matches`: `total_distance_m`, `max_speed_kmh`, `sprint_count`, `avg_heart_rate` 추가. 기존 row는 0으로 backfill.
  - `quarter_workouts`: `duration_seconds`, `distance_m`, `avg_speed_kmh`, `avg_heart_rate`, `max_heart_rate`, `sprint_count`, `active_energy_kcal` 추가. 기존 row는 0으로 backfill.
  - 시즌 집계 조회용 `(user_id, played_at)` 인덱스 추가.
- Match 저장 계약 확장:
  - `UpsertMatchRequest`: `totalDistanceM`, `maxSpeedKmh`, `sprintCount`, `avgHeartRate` 필드 추가.
  - `UpsertQuarterRequest`: `durationSeconds`, `distanceM`, `avgSpeedKmh`, `avgHeartRate`, `maxHeartRate`, `sprintCount`, `activeEnergyKcal` 필드 추가.
  - 기존 테스트/클라이언트 호환을 위해 metric request 필드는 기본 0을 허용한다.
  - Response DTO에도 동일 metric 필드를 노출한다.
- 통계 도메인 추가:
  - `stat/controller/SeasonStatController.kt`
    - `GET /users/me/seasons/{year}`
    - `GET /users/{userId}/seasons/{year}`
  - `stat/service/SeasonStatService.kt`
    - `getMySeasonStat(userId, year): SeasonStat`
    - `getFriendSeasonStat(viewerId, friendUserId, year): SeasonStat`
  - `stat/dto/SeasonStatDtos.kt`
    - `SeasonStatResponse`, `SeasonBestResponse`
- Repository:
  - `MatchStore.findAllByUserIdAndPlayedAtBetween(userId, startInclusive, endExclusive): List<Match>`
  - JPA query는 quarters lazy 초기화가 필요한 service 내부에서 처리한다.
- 정책:
  - 데이터 없는 연도는 200 + 0값.
  - 친구 통계는 `FriendshipAuthorizer.assertCanView` 선검증.
  - 연도는 MVP 범위에서 2000~2100만 허용하고 벗어나면 `VALIDATION_FAILED`.
  - 통계 계산은 백엔드 read-only 트랜잭션에서 수행한다.

## 3. 테스트 케이스 (Test Cases) — TDD 핵심

> **🔴 RED 먼저, 🟢 GREEN 다음, 🔵 REFACTOR 마지막**

### (3-A) 인수 시나리오 (Gherkin)

@stat @match
Feature: 시즌 통계 API
  Scenario: 로그인 사용자는 본인 시즌 통계를 조회한다
    Given 사용자가 2026년에 metric이 포함된 경기 2개를 저장했다
    When GET /users/me/seasons/2026 요청을 보낸다
    Then 200 응답에 총 거리, 골, 어시스트, 경기 수, 쿼터 수, 시즌 best가 집계된다

  Scenario: 경기 없는 연도도 0값 통계를 반환한다
    Given 로그인 사용자의 2025년 경기가 없다
    When GET /users/me/seasons/2025 요청을 보낸다
    Then 200 응답에 모든 누적 값과 best 값이 0으로 반환된다

  Scenario: accepted 친구의 시즌 통계를 조회한다
    Given 사용자 A와 사용자 B가 accepted 친구 관계다
    And B가 2026년에 metric이 포함된 경기를 저장했다
    When A가 GET /users/{B}/seasons/2026 요청을 보낸다
    Then 200 응답에 B의 시즌 통계가 반환된다

  Scenario: accepted 친구가 아니면 시즌 통계를 조회할 수 없다
    Given 사용자 A와 사용자 B가 친구 관계가 아니다
    When A가 GET /users/{B}/seasons/2026 요청을 보낸다
    Then 403 FRIEND_UNAUTHORIZED 응답을 받는다

### (3-B) 유스케이스 / 단위 테스트 케이스

Happy Path
- [ ] `MatchService.saveMatch` — match/quarter metric 필드를 저장하고 상세 응답으로 다시 노출한다.
- [ ] `SeasonStatService.getMySeasonStat` — 같은 연도 경기만 집계한다.
- [ ] `SeasonStatService.getFriendSeasonStat` — accepted 친구 권한 통과 후 대상 사용자 통계를 반환한다.

Unhappy Path
- [ ] `SeasonStatService.getFriendSeasonStat` — accepted 관계 없음은 `FRIEND_UNAUTHORIZED`.
- [ ] `SeasonStatService.getFriendSeasonStat` — 대상 없음/탈퇴는 `USER_NOT_FOUND`.
- [ ] controller — year 범위가 2000~2100 밖이면 `VALIDATION_FAILED`.

Edge Cases
- [ ] 경기 없는 연도는 0값을 반환한다.
- [ ] `best.longestMatchDistanceM`은 단일 경기 `totalDistanceM` 최댓값이다.
- [ ] `best.mostSprintCount`는 단일 경기 `sprintCount` 최댓값이다.

## 4. 검증 (Verification)

### 자동 검증
- 백엔드: `cd backend && ./gradlew test`
- 백엔드: `cd backend && ./gradlew compileKotlin`
- 백엔드: `cd backend && ./gradlew check`
- iOS: 자동 검증 없음 (사용자가 Xcode 에서 수동 빌드)

### 시나리오 검증 (수동)
- metric이 포함된 경기를 2개 저장한 뒤 `GET /users/me/seasons/2026` 응답의 합계와 best를 확인한다.
- accepted 친구의 token으로 `GET /users/{friendId}/seasons/2026`을 호출하면 같은 통계가 반환된다.
- 비친구 사용자는 `403 FRIEND_UNAUTHORIZED`로 차단된다.

### 커버리지
- acceptance test + service test로 집계/권한/빈 연도/검증 경계를 커버한다.

---

## (Optional) 위험도 / 롤백

Risk = Risky

DB 마이그레이션이 있고 `PUT /matches` 저장 계약이 확장된다. 기존 client 호환을 위해 새 metric request 필드는 기본 0으로 둔다. 롤백은 PR revert + 필요 시 추가 마이그레이션으로 새 metric 컬럼 drop.

## (Optional) 후속 / 관련 이슈

iOS 업로드 request에 metric 필드를 채우는 작업은 사용자가 Xcode에서 별도 반영한다. 친구 경기 DTO의 hideHeartRate 마스킹은 심박 필드가 response에 노출되면 추가 점검한다.

## (Optional) 학습 기록

Trigger: none

---

## TDD 작업 흐름

```
1. 위의 "3. 테스트 케이스" 섹션 채우기 (사용자가 결정)
2. 🔴 RED:
   - test-writer agent에게 위 케이스를 코드로 변환 위임
   - ./gradlew test (or Cmd+U) → 모두 실패 확인
3. 🟢 GREEN:
   - 한 케이스씩 최소 구현
   - 테스트 통과
4. 🔵 REFACTOR:
   - 중복 제거, 메서드 분리, 네이밍 정리
   - 테스트 여전히 통과
5. 다음 케이스 반복
6. 모든 케이스 통과 → "4. 검증" 섹션의 명령 실행
7. self-heal/Critical/누락 테스트가 있었으면 학습 기록 판단
8. PR 생성 (/pr-guide)
```

> 완료 시: `상태` 필드를 `done`으로 변경하고 PR 본문에 본 파일 링크 첨부.
