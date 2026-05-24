# EXEC_PLAN — venue-update-delete-api

| 항목 | 값 |
|---|---|
| Task | venue-update-delete-api |
| Type | feature |
| Branch | feature/venue-update-delete-api |
| Worktree | /Users/opix/Developer/kicklog/.worktrees/venue-update-delete-api |
| Port | 9000 |
| 생성 시각 | 2026-05-24 15:03 |
| 상태 | `done` |
| 개발 방식 | **TDD (Red → Green → Refactor)** |

---

> **단순화 + TDD 원칙**:
> - 본 템플릿은 GearShow의 8섹션을 KickLog용 **4섹션 + optional**로 축소 (Ralph: "계획은 일회용·짧게")
> - **테스트 케이스 섹션**을 통해 TDD 강제 — 구현 전에 테스트 케이스 명시
> - 30줄 미만의 작은 변경은 EXEC_PLAN 자체가 면제됨 (`enforce-plan.sh`)

## 1. 목표 (Goal)

명세에 남아 있는 개인 운동장 이름 수정/삭제 API를 구현한다. 삭제 시 과거 경기 기록은 유지하되 `matches.venue_id`만 `NULL`로 바꿔 경기 데이터 손실을 막는다.

## 2. 접근 (Approach)

- DB: `V8__venue_delete_set_null.sql`
  - `matches.venue_id` nullable 변경
  - 기존 FK를 `ON DELETE SET NULL`로 재생성
- Match 모델/DTO:
  - `Match.venueId: Long?`
  - `MatchDetailResponse.venueId`, `MatchSummaryResponse.venueId` nullable
  - 저장 request는 기존 호환을 위해 `venueId` 필수 유지. 삭제 이후 조회 응답에서만 null 가능.
- Venue DTO:
  - `UpdateVenueRequest(name: String)` 추가
- Venue service:
  - `updateVenue(userId, venueId, name): Venue`
  - `deleteVenue(userId, venueId)`
  - 본인 소유 검증: 없는 venue는 `VENUE_NOT_FOUND`, 남의 venue는 `VENUE_NOT_OWNED`
  - 같은 사용자 내 이름 중복은 `VENUE_NAME_DUPLICATE`
- Venue controller:
  - `PATCH /venues/{venueId}`
  - `DELETE /venues/{venueId}`
- Repository:
  - 기존 Spring Data `delete` 사용. DB FK가 match venue를 null 처리한다.

## 3. 테스트 케이스 (Test Cases) — TDD 핵심

> **🔴 RED 먼저, 🟢 GREEN 다음, 🔵 REFACTOR 마지막**

### (3-A) 인수 시나리오 (Gherkin)

@venue
Feature: 운동장 수정/삭제
  Scenario: 로그인 사용자는 본인 운동장 이름을 수정한다
    Given 로그인 사용자의 운동장이 있다
    When PATCH /venues/{id} 로 이름 수정을 요청한다
    Then 200 응답에 수정된 이름이 반환된다
    And GET /venues/{id} 로 수정된 이름을 조회할 수 있다

  Scenario: 로그인 사용자는 본인 운동장을 삭제한다
    Given 로그인 사용자의 운동장이 있다
    When DELETE /venues/{id} 요청을 보낸다
    Then 204 응답이 반환된다
    And GET /venues/{id} 는 404 VENUE_NOT_FOUND를 반환한다

  Scenario: 운동장 삭제 후 기존 경기의 venueId는 null로 조회된다
    Given 로그인 사용자의 운동장과 해당 운동장에 저장된 경기가 있다
    When DELETE /venues/{id} 요청을 보낸다
    Then GET /matches/{matchId} 응답의 venueId는 null이다

  Scenario: 다른 사용자의 운동장은 수정하거나 삭제할 수 없다
    Given 다른 사용자의 운동장이 있다
    When PATCH /venues/{id} 또는 DELETE /venues/{id} 요청을 보낸다
    Then 403 VENUE_NOT_OWNED 응답을 받는다

### (3-B) 유스케이스 / 단위 테스트 케이스

Happy Path
- [x] `VenueService.updateVenue` — 본인 운동장 이름 수정
- [x] `VenueService.deleteVenue` — 본인 운동장 삭제

Unhappy Path
- [x] `VenueService.updateVenue` — 같은 사용자 내 이름 중복은 `VENUE_NAME_DUPLICATE`
- [x] `VenueService.updateVenue/deleteVenue` — 없는 운동장은 `VENUE_NOT_FOUND`
- [x] `VenueService.updateVenue/deleteVenue` — 남의 운동장은 `VENUE_NOT_OWNED`

Edge Cases
- [x] 이름은 trim 후 저장한다.
- [x] 삭제된 venue를 참조하던 match는 조회 시 `venueId=null`을 반환한다.

## 4. 검증 (Verification)

### 자동 검증
- 백엔드: `cd backend && ./gradlew test`
- 백엔드: `cd backend && ./gradlew compileKotlin`
- 백엔드: `cd backend && ./gradlew check`
- iOS: 자동 검증 없음 (사용자가 Xcode 에서 수동 빌드)

### 시나리오 검증 (수동)
- 운동장 생성 후 이름을 수정하고 상세 조회로 반영을 확인한다.
- 운동장 삭제 후 상세 조회는 404, 해당 경기 상세의 `venueId`는 null인지 확인한다.

### 커버리지
- acceptance test와 service test로 수정/삭제/권한/중복/venue null 경계를 커버한다.

---

## (Optional) 위험도 / 롤백

Risk = Risky

DB FK 변경과 `Match.venueId` nullable 응답 변경이 포함된다. 롤백은 PR revert 후 필요 시 추가 마이그레이션으로 FK를 기존 `NOT NULL`/기본 FK로 복구한다.

## (Optional) 후속 / 관련 이슈

운동장 삭제 이후 iOS에서 경기 상세 venue 표시를 "운동장 없음"으로 처리해야 한다.

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
