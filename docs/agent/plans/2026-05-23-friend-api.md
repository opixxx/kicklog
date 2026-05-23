# EXEC_PLAN — friend-api

| 항목 | 값 |
|---|---|
| Task | friend-api |
| Type | feature |
| Branch | feature/friend-api |
| Worktree | /Users/opix/Developer/kicklog/.worktrees/friend-api |
| Port | 9000 |
| 생성 시각 | 2026-05-23 17:55 |
| 상태 | `done` |
| 개발 방식 | **TDD (Red → Green → Refactor)** |

---

> **단순화 + TDD 원칙**:
> - 본 템플릿은 GearShow의 8섹션을 KickLog용 **4섹션 + optional**로 축소 (Ralph: "계획은 일회용·짧게")
> - **테스트 케이스 섹션**을 통해 TDD 강제 — 구현 전에 테스트 케이스 명시
> - 30줄 미만의 작은 변경은 EXEC_PLAN 자체가 면제됨 (`enforce-plan.sh`)

## 1. 목표 (Goal)

PRD와 API 명세의 친구 관계 API 5개 엔드포인트를 백엔드에 구현한다.
MVP의 친구 탭과 친구 데이터 read-only 공유의 기반이 되는 양방향 친구 관계를 정렬 pair 1 row 모델로 저장한다.

## 2. 접근 (Approach)

- `backend/src/main/resources/db/migration/V6__friendships.sql`
  - `friendships(user_low_id, user_high_id, status, initiated_by_id, accepted_at)` 추가
  - `friend_invitations(token, inviter_id, expires_at, revoked_at, use_count)` 추가
  - `(user_low_id, user_high_id)` UNIQUE, `user_low_id < user_high_id` CHECK
- `com.opixxx.kicklog.friend`
  - `Friendship`, `FriendInvitation` 엔티티
  - `FriendshipStore` / `JpaFriendshipStore`
  - `FriendshipService`
    - `listAccepted(userId: Long): List<FriendshipSummary>`
    - `listReceivedPending(userId: Long): List<PendingFriendshipSummary>`
    - `request(userId: Long, command: CreateFriendshipCommand): CreateFriendshipResult`
    - `accept(userId: Long, friendshipId: Long): AcceptFriendshipResult`
    - `delete(userId: Long, friendshipId: Long)`
  - `FriendshipController`
- API 계약
  - `GET /friendships`
  - `GET /friendships/pending`
  - `POST /friendships` with exactly one of `token`, `targetUserId`
  - `PATCH /friendships/{id}` with `action=accept`
  - `DELETE /friendships/{id}`
- 트랜잭션 / 권한 규칙
  - 생성/수락/삭제는 `@Transactional`, 조회는 `readOnly = true`
  - 자기 자신 요청은 400, 이미 accepted 또는 같은 방향 pending은 409
  - 반대 방향 pending 요청이 있으면 새 row를 만들지 않고 자동 수락
  - 수락은 받은 pending 요청만 가능하며 보낸 요청 수락은 403
  - 삭제는 관계 당사자만 가능하며 비당사자는 403

## 3. 테스트 케이스 (Test Cases) — TDD 핵심

> **🔴 RED 먼저, 🟢 GREEN 다음, 🔵 REFACTOR 마지막**

### (3-A) 인수 시나리오 (Gherkin)

@friend @smoke
Feature: 친구 관계 API
  Scenario: targetUserId로 친구 요청을 보내고 상대가 수락한다 (Happy)
    Given 사용자 A와 사용자 B가 있다
    When A가 B에게 POST /friendships 요청을 보낸다
    Then 201 응답과 pending 관계를 받는다
    When B가 PATCH /friendships/{id} accept 요청을 보낸다
    Then 200 응답과 accepted 관계를 받는다
    And A의 GET /friendships 응답에 B가 보인다

  Scenario: 보낸 친구 요청은 본인이 수락할 수 없다 (Unhappy)
    Given 사용자 A가 사용자 B에게 pending 친구 요청을 보냈다
    When A가 PATCH /friendships/{id} accept 요청을 보낸다
    Then 403 FRIEND_NOT_RECIPIENT 응답을 받는다

  Scenario: 관계 당사자가 아니면 친구 관계를 삭제할 수 없다 (Unhappy)
    Given 사용자 A와 사용자 B의 accepted 친구 관계가 있다
    When 사용자 C가 DELETE /friendships/{id} 요청을 보낸다
    Then 403 FRIEND_NOT_PARTICIPANT 응답을 받는다

### (3-B) 유스케이스 / 단위 테스트 케이스

Happy Path
- [x] `FriendshipService.request` — targetUserId로 pending 관계 생성
- [x] `FriendshipService.accept` — 받은 pending 요청 수락
- [x] `FriendshipService.listAccepted` — accepted 관계만 상대 사용자 정보와 함께 반환
- [x] `FriendshipService.listReceivedPending` — 내가 받은 pending 요청만 반환
- [x] `FriendshipService.delete` — accepted/pending 관계 삭제

Unhappy Path
- [x] `FriendshipService.request` — 자기 자신 요청은 `FRIEND_SELF_REQUEST`
- [x] `FriendshipService.request` — 둘 다 없거나 둘 다 있으면 `FRIEND_INVALID_REQUEST`
- [x] `FriendshipService.request` — 이미 accepted 또는 같은 방향 pending이면 `FRIEND_ALREADY_EXISTS`
- [x] `FriendshipService.accept` — 보낸 요청 수락 시 `FRIEND_NOT_RECIPIENT`
- [x] `FriendshipService.delete` — 비당사자 삭제 시 `FRIEND_NOT_PARTICIPANT`
- [x] `FriendshipService.request` — token 요청, 만료/취소 token 예외
- [x] `FriendshipService.accept` — 비당사자가 accepted 상태를 추론하지 못하도록 403 유지

## 4. 검증 (Verification)

### 자동 검증
- 백엔드: `cd backend && ./gradlew test`
- 백엔드: `cd backend && ./gradlew compileKotlin`
- 백엔드: `cd backend && ./gradlew check`
- 결과: 세 명령 모두 통과. PostgreSQL Testcontainers 기반 Flyway/JPA validate 테스트도 통과했으며 컨테이너는 테스트 종료 후 정리됨.

### 시나리오 검증 (수동)
- JWT 사용자 A가 B에게 친구 요청을 보내면 A는 pending 생성 응답을 받고 B의 pending 목록에 A가 보인다.
- B가 요청을 수락하면 A/B 양쪽 친구 목록에 상대가 보인다.
- 관계 당사자가 아닌 사용자는 수락/삭제할 수 없다.

### 커버리지
- 새 friend 서비스의 Happy/Unhappy 핵심 분기 테스트 포함

---

## (Optional) 위험도 / 롤백

Risk = Risky

DB 마이그레이션이 포함된다. 롤백은 friend API PR revert 후 신규 환경 기준 `friendships`, `friend_invitations` 테이블을 제거하는 수동 SQL로 처리한다.

## (Optional) 후속 / 관련 이슈

초대 링크 발급/폐기 API와 친구 경기/시즌 read-only API는 후속 PR 범위다.

## (Optional) 학습 기록

Trigger: none
Root cause: review-major — 동시 친구 요청 unique 충돌을 같은 트랜잭션 안에서 복구하려 했다.
Prevention: insert 시도와 충돌 후 재조회/자동수락을 별도 TransactionTemplate 경계로 분리했다.
Promoted to: none

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
