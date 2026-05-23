# EXEC_PLAN — match-save-api

| 항목 | 값 |
|---|---|
| Task | match-save-api |
| Type | feature |
| Branch | feature/match-save-api |
| Worktree | /Users/opix/Developer/kicklog/.worktrees/match-save-api |
| Port | 9000 |
| 생성 시각 | 2026-05-23 14:49 |
| 상태 | `done` |
| 개발 방식 | **TDD (Red → Green → Refactor)** |

---

> **단순화 + TDD 원칙**:
> - 본 템플릿은 GearShow의 8섹션을 KickLog용 **4섹션 + optional**로 축소 (Ralph: "계획은 일회용·짧게")
> - **테스트 케이스 섹션**을 통해 TDD 강제 — 구현 전에 테스트 케이스 명시
> - 30줄 미만의 작은 변경은 EXEC_PLAN 자체가 면제됨 (`enforce-plan.sh`)

## 1. 목표 (Goal)

iOS가 SwiftData/HealthKit 기준으로 만든 경기 라벨링 결과를 서버에 백업할 수 있도록 경기 저장 API를 추가한다. 저장은 사용자 + `clientMatchId` 기준으로 멱등하게 동작하며, 저장 직후 상세 조회와 내 경기 목록 조회를 지원한다. 기존 offset 기반 목록 문서는 이번 작업에서 cursor 기반 목록 계약으로 갱신한다.

## 2. 접근 (Approach)

- 문서: `docs/architecture/api-conventions.md`, `docs/spec/api-spec.md`의 경기 목록 페이징을 `cursor/size` 방식으로 변경한다.
- DB: `V5__matches.sql`에 `matches`, `quarter_workouts` 테이블을 추가한다. `matches(user_id, client_match_id)` 유니크 인덱스로 멱등 저장을 보장하고, 목록 조회용 `(user_id, played_at desc, id desc)` 인덱스를 둔다.
- 도메인: `match` 패키지에 `Match` aggregate와 `QuarterWorkout` 내부 객체를 둔다. `Match.replaceWith(...)`로 PUT 업데이트 시 쿼터를 통째로 교체한다.
- API:
  - `PUT /matches/{clientMatchId}`: 신규면 `201`, 기존이면 `200`.
  - `GET /matches/{id}`: 본인 경기 상세 조회.
  - `GET /matches/by-client-id/{clientMatchId}`: 저장 직후 iOS 확인용 상세 조회.
  - `GET /matches?cursor={playedAt,id}&size=20`: 내 경기 목록 최신순 cursor pagination. cursor는 `playedAt`과 `id`를 담은 URL-safe 토큰으로 응답의 `nextCursor`에만 노출한다.
- 권한/정책: `venueId`가 없으면 `VENUE_NOT_FOUND`, 다른 사용자의 venue면 `VENUE_NOT_OWNED`를 반환한다. 경기 상세에서 남의 경기는 `MATCH_NOT_OWNED`, 없는 경기는 `MATCH_NOT_FOUND`로 구분한다.

## 3. 테스트 케이스 (Test Cases) — TDD 핵심

> **🔴 RED 먼저, 🟢 GREEN 다음, 🔵 REFACTOR 마지막**

### (3-A) 인수 시나리오 (Gherkin)

```gherkin
@match @smoke
Feature: 경기 저장
  Scenario: 로그인 사용자는 본인 운동장에 경기와 쿼터를 저장하고 clientMatchId로 다시 조회한다
    Given 로그인 사용자의 운동장이 있다
    When PUT /matches/{clientMatchId} 로 경기와 쿼터 저장을 요청한다
    Then 201 응답과 경기 상세가 반환된다
    And GET /matches/by-client-id/{clientMatchId} 로 같은 경기 상세를 조회할 수 있다

  Scenario: 같은 사용자와 같은 clientMatchId로 다시 저장하면 기존 경기를 덮어쓴다
    Given 로그인 사용자가 같은 clientMatchId로 저장한 경기가 있다
    When PUT /matches/{clientMatchId} 로 다른 스코어와 쿼터를 저장한다
    Then 200 응답과 수정된 경기 상세가 반환된다
    And 쿼터 목록은 새 요청 값으로 교체된다

  Scenario: 내 경기 목록은 최신순 cursor 방식으로 다음 페이지를 제공한다
    Given 로그인 사용자의 경기가 3개 있다
    When GET /matches?size=2 로 목록을 조회한다
    Then 최신 경기 2개와 nextCursor가 반환된다
    When nextCursor로 다음 페이지를 조회한다
    Then 남은 경기 1개와 null nextCursor가 반환된다

  Scenario: 다른 사용자의 운동장으로 경기를 저장하면 거부된다
    Given 다른 사용자의 운동장이 있다
    When PUT /matches/{clientMatchId} 로 그 운동장에 저장을 요청한다
    Then 403 VENUE_NOT_OWNED 응답이 반환된다

  Scenario: 없는 운동장으로 경기를 저장하면 실패한다
    When PUT /matches/{clientMatchId} 로 없는 venueId를 보낸다
    Then 404 VENUE_NOT_FOUND 응답이 반환된다
```

### (3-B) 유스케이스 / 단위 테스트 케이스

- `MatchService.saveMatch(userId, clientMatchId, command)` — 신규 저장 / 기존 저장 덮어쓰기 / 본인 venue 검증 / 남의 venue 403 / 없는 venue 404.
- `MatchService.listMyMatches(userId, cursor, size)` — 최신순 `(playedAt desc, id desc)` 조회 / 다음 커서 생성 / 마지막 페이지 `nextCursor=null`.
- `Match.create(...)`, `Match.replaceWith(...)` — 쿼터 1~4개 허용 / 중복 quarterNumber 거부 / 쿼터 교체 시 기존 값 제거.
- `MatchCursor.encode/decode` — 정상 토큰 round-trip / 잘못된 토큰은 `VALIDATION_FAILED`.

## 4. 검증 (Verification)

### 자동 검증
- 백엔드: `cd backend && ./gradlew check`
- iOS: 자동 검증 없음 (사용자가 Xcode 에서 수동 빌드)

### 시나리오 검증 (수동)
- 로그인 토큰으로 운동장을 저장한 뒤 `PUT /matches/{clientMatchId}`를 호출하면 `201`과 상세가 반환된다.
- 같은 `clientMatchId`로 다시 저장하면 `200`과 변경된 상세가 반환된다.
- `GET /matches?size=20`은 최신순 목록과 `nextCursor`를 반환한다.

### 커버리지
- acceptance test와 service test로 저장/조회/권한/커서 경계를 검증한다.

---

## (Optional) 위험도 / 롤백

Risk = Caution. 새 테이블 추가 마이그레이션이며 기존 API 동작에는 영향이 없다. 문서의 목록 페이징 계약은 offset에서 cursor로 변경된다.

## (Optional) 후속 / 관련 이슈

친구 경기 목록과 경기 삭제 API는 문서상 후속 범위로 남긴다.

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
