# EXEC_PLAN — friend-match-read-api

| 항목 | 값 |
|---|---|
| Task | friend-match-read-api |
| Type | feature |
| Branch | feature/friend-match-read-api |
| Worktree | /Users/opix/Developer/kicklog/.worktrees/friend-match-read-api |
| Port | 9000 |
| 생성 시각 | 2026-05-23 19:40 |
| 상태 | `done` |
| 개발 방식 | **TDD (Red → Green → Refactor)** |

---

> **단순화 + TDD 원칙**:
> - 본 템플릿은 GearShow의 8섹션을 KickLog용 **4섹션 + optional**로 축소 (Ralph: "계획은 일회용·짧게")
> - **테스트 케이스 섹션**을 통해 TDD 강제 — 구현 전에 테스트 케이스 명시
> - 30줄 미만의 작은 변경은 EXEC_PLAN 자체가 면제됨 (`enforce-plan.sh`)

## 1. 목표 (Goal)

친구의 경기 목록/상세 read-only API를 구현한다.
친구 데이터 경로는 반드시 `FriendshipAuthorizer`를 통과해 IDOR를 방지하고, 후속 시즌 통계 API가 재사용할 권한 경계를 만든다.

## 2. 접근 (Approach)

- `friend/service/FriendshipAuthorizer.kt`
  - `assertCanView(viewerId: Long, targetUserId: Long): User`
  - 대상 사용자가 없거나 탈퇴했으면 `USER_NOT_FOUND`
  - accepted friendship이 없으면 `FRIEND_UNAUTHORIZED`
  - 자기 자신은 허용한다. 실제 본인 경기 API는 `/matches`지만, 동일 path 접근이 IDOR로 오탐되지 않게 둔다.
- `match/controller/MatchController.kt`
  - `GET /users/{userId}/matches?cursor=...&size=20`
  - `GET /users/{userId}/matches/{id}`
- `match/service/MatchService.kt`
  - `listFriendMatches(viewerId, friendUserId, cursor, size): CursorResponse<Match>`
  - `getFriendMatch(viewerId, friendUserId, matchId): Match`
  - friend path는 `FriendshipAuthorizer.assertCanView` 선검증 후 target user match만 조회
- `match/dto/MatchDtos.kt`
  - 기존 `MatchSummaryResponse` / `MatchDetailResponse` 재사용
  - 현재 match DTO에는 심박 필드가 없어 `hideHeartRate` 마스킹 대상 없음. 심박 필드 추가 PR에서 mapper 옵션을 확장한다.
- DB 마이그레이션 없음

## 3. 테스트 케이스 (Test Cases) — TDD 핵심

> **🔴 RED 먼저, 🟢 GREEN 다음, 🔵 REFACTOR 마지막**

### (3-A) 인수 시나리오 (Gherkin)

@friend @match
Feature: 친구 경기 read-only API
  Scenario: accepted 친구의 경기 목록과 상세를 조회한다 (Happy)
    Given 사용자 A와 사용자 B가 accepted 친구 관계다
    And B가 경기를 저장했다
    When A가 GET /users/{B}/matches 요청을 보낸다
    Then 200 응답에 B의 경기 목록이 보인다
    When A가 GET /users/{B}/matches/{matchId} 요청을 보낸다
    Then 200 응답에 B의 경기 상세가 보인다

  Scenario: accepted 친구가 아니면 친구 경기 목록을 조회할 수 없다 (Unhappy)
    Given 사용자 A와 사용자 B가 친구 관계가 아니다
    When A가 GET /users/{B}/matches 요청을 보낸다
    Then 403 FRIEND_UNAUTHORIZED 응답을 받는다

  Scenario: 친구 관계여도 다른 사용자의 matchId 상세는 조회할 수 없다 (Unhappy)
    Given 사용자 A와 사용자 B가 accepted 친구 관계다
    And 사용자 C가 경기를 저장했다
    When A가 GET /users/{B}/matches/{C의 matchId} 요청을 보낸다
    Then 404 MATCH_NOT_FOUND 응답을 받는다

### (3-B) 유스케이스 / 단위 테스트 케이스

Happy Path
- [ ] `FriendshipAuthorizer.assertCanView` — accepted friendship이면 대상 사용자 반환
- [ ] `MatchService.listFriendMatches` — 권한 통과 후 대상 사용자 경기 목록 반환
- [ ] `MatchService.getFriendMatch` — 권한 통과 후 대상 사용자 경기 상세 반환

Unhappy Path
- [ ] `FriendshipAuthorizer.assertCanView` — 대상 없음/탈퇴는 `USER_NOT_FOUND`
- [ ] `FriendshipAuthorizer.assertCanView` — accepted 관계 없음은 `FRIEND_UNAUTHORIZED`
- [ ] `MatchService.getFriendMatch` — 다른 사용자의 matchId는 `MATCH_NOT_FOUND`

## 4. 검증 (Verification)

### 자동 검증
- 백엔드: `cd backend && ./gradlew test`
- 백엔드: `cd backend && ./gradlew compileKotlin`
- 백엔드: `cd backend && ./gradlew check`

### 시나리오 검증 (수동)
- accepted 친구는 상대 경기 목록/상세를 볼 수 있다.
- 친구가 아닌 사용자는 403으로 차단된다.
- 권한이 있더라도 path의 friendUserId 소유가 아닌 matchId는 404로 차단된다.

### 커버리지
- Controller 인수 테스트 + Authorizer/Service 단위 테스트로 Happy/Unhappy 경로 커버

---

## (Optional) 위험도 / 롤백

Risk = Caution

새 read-only API 추가이며 DB 마이그레이션은 없다. 롤백은 PR revert로 처리한다.

## (Optional) 후속 / 관련 이슈

심박수 관련 DTO 필드가 추가되면 friend path에서 `hideHeartRate` 마스킹을 mapper에 적용한다.
다음 작업은 `season-stat-api`에서 `FriendshipAuthorizer`를 재사용한다.

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
