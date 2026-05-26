# EXEC_PLAN — matches-team-goals

| 항목 | 값 |
|---|---|
| Task | matches-team-goals |
| Type | feature |
| Branch | feature/matches-team-goals |
| Worktree | /Users/opix/Developer/kicklog/.worktrees/matches-team-goals |
| Port | 9000 |
| 생성 시각 | 2026-05-27 01:43 |
| 상태 | `done` |
| 개발 방식 | **TDD (Red → Green → Refactor)** |

---

## 1. 목표 (Goal)

라벨링 화면에서 "본인 골" 만 입력받아 매치 스코어로 표시하던 구조가 의미적으로 잘못되어 있다 — 팀 스포츠 매치 스코어는 "팀 전체 골 vs 상대 골" 이 맞다. 또한 "결과 (승/무/패)" 토글은 골 수와 별개로 입력받게 되어 있어서 0:0인데 "승"으로 저장되는 모순이 가능하다.

본 작업은 `matches.team_goals` 컬럼을 신설해 팀 전체 골을 별도 보존하고, `result` 는 백엔드에서 `team_goals` vs `opponent_goals` 로 자동 derive 한다. 입력 UX 가 단순해지고 (`결과` 토글 제거), 데이터 무결성도 강화된다 (모순 불가능).

## 2. 접근 (Approach)

### 2.1 DB 마이그레이션 — V10

```sql
ALTER TABLE matches
    ADD COLUMN team_goals SMALLINT;
ALTER TABLE matches
    ADD CONSTRAINT matches_team_goals_min CHECK (team_goals IS NULL OR team_goals >= 0);
ALTER TABLE matches
    ADD CONSTRAINT matches_team_goals_gte_user_goals CHECK (team_goals IS NULL OR team_goals >= goals);
```

> 기존 매치 (team_goals NULL) 은 그대로 NULL — 사용자가 추후 라벨링 수정 시 채움. 호환성 깨짐 없음.

### 2.2 도메인 모델 — `Match` 엔티티

- `teamGoals: Int?` 필드 추가 (nullable, 미입력 vs 0 구분)
- `replaceWith(command)` 안에서 `result = MatchResultType.derive(teamGoals, opponentGoals)` 호출 → command.result 무시
- `companion object Match.create(...)` 에서도 `teamGoals = null` 초기화

### 2.3 도메인 enum — `MatchResultType`

새 정적 메서드 추가:
```kotlin
fun derive(teamGoals: Int?, opponentGoals: Int?): MatchResultType? {
    if (teamGoals == null || opponentGoals == null) return null
    return when {
        teamGoals > opponentGoals -> WIN
        teamGoals < opponentGoals -> LOSS
        else -> DRAW
    }
}
```

### 2.4 DTO — `UpsertMatchRequest` / `MatchDetailResponse` / `MatchSummaryResponse`

- Request: `result` 필드 **제거**, `teamGoals: Int?` 추가 (`@Min(0)`)
- Request: cross-field validation — `teamGoals >= goals` (있을 때만). `@AssertTrue` getter 메서드로 검증.
- Response (Detail/Summary): `teamGoals: Int?` 추가, `result` 유지 (derive 된 값)
- Command: `UpsertMatchCommand.teamGoals: Int?` 추가, `result` 필드 제거 (entity 에서 derive)

### 2.5 Service

`MatchService.saveMatch()` 는 변경 없음 — entity 가 derive 책임을 가짐 (rich aggregate).

### 2.6 ErrorCode

- 이미 있는 `MATCH_*` 외에 cross-field validation 은 Bean Validation 의 기본 400 응답 활용 (별도 ErrorCode 불필요).
- DB CHECK 위반 시 PSQLException → `GlobalExceptionHandler` 가 500 으로 잡힐 가능성 — DTO Validation 단에서 막아서 DB 까지 도달하지 않게 함.

### 2.7 ADR 문서 갱신

`docs/adr/0003-data-model-and-api.md` 의 matches 테이블 정의에 `team_goals SMALLINT` + CHECK 제약 추가 (line 270~).

### 2.8 외부 클라이언트 (iOS) — 본 하네스 대상 아님

iOS 는 별도 작업으로 진행 (백엔드 PR 머지 후 또는 동시 적용). 본 EXEC_PLAN 범위 외.

## 3. 테스트 케이스 (Test Cases) — TDD 핵심

### (3-A) 인수 시나리오 (Gherkin)

```gherkin
@match @smoke
Feature: 매치 라벨링 — 팀 전체 골 + 결과 자동 derive
  사용자가 팀 전체 골과 상대 골을 입력하면 매치 결과(승/무/패)는 자동 계산된다.

  Background:
    Given 인증된 사용자가 venue 1번을 소유하고 있다

  Scenario: 팀골 > 상대골 → result "WIN" (Happy)
    When PUT /matches/{clientMatchId} 에 goals=1, teamGoals=3, opponentGoals=2 로 저장
    Then 200 응답에 result 는 "WIN"
    And teamGoals 는 3

  Scenario: 팀골 == 상대골 → result "DRAW"
    When PUT /matches/{clientMatchId} 에 goals=0, teamGoals=1, opponentGoals=1 로 저장
    Then 200 응답에 result 는 "DRAW"

  Scenario: 팀골 < 상대골 → result "LOSS"
    When PUT /matches/{clientMatchId} 에 goals=0, teamGoals=0, opponentGoals=2 로 저장
    Then 200 응답에 result 는 "LOSS"

  Scenario: teamGoals 미입력 → result null
    When PUT /matches/{clientMatchId} 에 teamGoals=null, opponentGoals=null 로 저장
    Then 200 응답에 result 는 null
    And teamGoals 는 null

  @edge-case
  Scenario: teamGoals < goals (본인이 2골인데 팀 1골) → 400 (Unhappy)
    When PUT /matches/{clientMatchId} 에 goals=2, teamGoals=1, opponentGoals=0 로 저장
    Then 400 응답
    And 응답 message 에 "팀 전체 골" 포함

  @edge-case
  Scenario: client 가 보낸 result 필드는 무시되고 derive 값으로 저장 (Unhappy 보호)
    When PUT /matches/{clientMatchId} 에 teamGoals=3, opponentGoals=2 로 저장 (result 필드는 Request DTO 에서 제거됨)
    Then 200 응답에 result 는 derive 된 "WIN" — 클라이언트가 어떤 값을 보내든 영향 없음
```

### (3-B) 유스케이스 / 단위 테스트 케이스

- `MatchResultType.derive(teamGoals, opponentGoals)` 단위
  - (null, null) → null
  - (null, 1) / (1, null) → null
  - (2, 1) → WIN, (1, 2) → LOSS, (1, 1) → DRAW
  - (0, 0) → DRAW
- `Match.replaceWith(command)` 통합 (Testcontainers)
  - command.teamGoals 가 set 되면 entity.teamGoals 와 result 모두 정상 derive
  - command.teamGoals = null 이면 entity.teamGoals = null + result = null
- `UpsertMatchRequest` validation 단위
  - `teamGoals = -1` → 400
  - `teamGoals = 1, goals = 2` → 400 (cross-field)
  - `teamGoals = null, goals = 2` → 통과 (모름 상태)
  - `teamGoals = 2, goals = 2` → 통과 (동일)

### 테스트 작성자
- 백엔드 → `backend-test-writer` agent

## 4. 검증 (Verification)

### 자동 검증
```bash
cd backend && ./gradlew test
cd backend && ./gradlew check
```

- 새 V10 마이그레이션이 기존 DB 위에 클린 적용
- 모든 인수 시나리오 (3-A) 통과
- 모든 단위 (3-B) 통과
- 기존 매치 관련 테스트 회귀 없음

### 시나리오 검증 (수동, 사용자 책임)
- iOS 빌드 후 라벨링 화면에서 결과 토글이 사라지고 "팀 전체 골" 입력 행이 추가됨
- 본인 2골, 팀 3골, 상대 2골 라벨링 → 매치 카드 "3-2 승" 표시
- 본인 1골, 팀 1골, 상대 1골 → "1-1 무"
- 팀 0골, 상대 0골 (미입력 NULL) → 결과 표시 "—"

### 커버리지
- 새 `MatchResultType.derive` + cross-field validator 메서드는 100% 커버
- 전체 평균 70% 이상 유지

---

## (Optional) 위험도 / 롤백

**Risk**: Caution

- DB 마이그레이션은 NULL 컬럼 추가 + CHECK 제약만 → 기존 데이터 영향 없음
- Request DTO 에서 `result` 필드 제거는 Breaking Change 지만 **iOS 가 1차 SoT 이고 백엔드는 백업** 이라 영향 최소. iOS 적용 전까지는 client 가 `result` 보내도 server 가 무시 (Jackson UnknownProperty 기본 무시) — graceful.

**롤백**:
```sql
ALTER TABLE matches DROP CONSTRAINT matches_team_goals_gte_user_goals;
ALTER TABLE matches DROP CONSTRAINT matches_team_goals_min;
ALTER TABLE matches DROP COLUMN team_goals;
```

## (Optional) 후속 / 관련 이슈

- **iOS 적용** (본 PR 머지 후 별도 작업):
  - `Match.teamGoals: Int?` 추가
  - `LabelingScreen` — 결과(승/무/패) 토글 제거 + "팀 전체 골" stepper 추가
  - `KLMatchRow` 스코어 표시: `userGoals - opponentGoals` → `teamGoals - opponentGoals`
  - `MatchDTO` / `MatchSyncService` 매핑 동기화
- 시즌 집계 (stat) 영역은 영향 없음 (현재 goals/opponentGoals 합산 안 함)

### code-reviewer 잔여 후속 (본 PR 스코프 외)

- **Major #4**: `assists <= teamGoals - goals` cross-field 검증 추가 — 1인 사이드 우선순위에 따라 보류. iOS UX 가이드만으로 충분하다고 판단.
- **Major #5**: `goals` NOT NULL vs `teamGoals` nullable 비대칭 — ADR-0003 에 정책 명시 완료. 컬럼 nullable 통일은 추가 마이그레이션 필요해서 보류.
- **Minor #7**: `Match.create()` 의 `result = null` 명시 제거(default 활용) — 가독성 취향.
- **Minor #9**: V10 CHECK 제약명 일관성 — `matches_team_goals_gte_user_goals` vs 실제 컬럼 `goals` 표기 차. 후속 rename 시 정정.
- **Suggestion S1**: `Score(team, opponent)` VO 도입 — 두 Int? 인자 순서 헷갈림 방지. 후속 리팩.
- **Suggestion S4**: 인수 테스트의 응답 JSON 검증을 DB row 직접 조회로 보강 — Controller vs DB 분기 보호선 강화.

## (Optional) 학습 기록

해당 없음 (작성 시점)

---

## TDD 작업 흐름

```
1. 위 "3. 테스트 케이스" → backend-test-writer agent 위임 (Phase 2 진입 시)
2. 🔴 RED: ./gradlew test → 의도한 이유로 실패 확인
3. 🟢 GREEN: V10 + Entity + DTO + Service 순서로 최소 구현
4. 🔵 REFACTOR: derive() 추출, validation cross-field 헬퍼 등 정리
5. 모든 케이스 통과 → "4. 검증" 명령 실행
6. ADR-0003 문서 갱신
7. PR 생성 (/pr-guide)
```

> 완료 시: `상태` 필드를 `done` 으로 변경하고 PR 본문에 본 파일 링크 첨부.
