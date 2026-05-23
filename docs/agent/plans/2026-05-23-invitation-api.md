# EXEC_PLAN — invitation-api

| 항목 | 값 |
|---|---|
| Task | invitation-api |
| Type | feature |
| Branch | feature/invitation-api |
| Worktree | /Users/opix/Developer/kicklog/.worktrees/invitation-api |
| Port | 9000 |
| 생성 시각 | 2026-05-23 19:19 |
| 상태 | `done` |
| 개발 방식 | **TDD (Red → Green → Refactor)** |

---

> **단순화 + TDD 원칙**:
> - 본 템플릿은 GearShow의 8섹션을 KickLog용 **4섹션 + optional**로 축소 (Ralph: "계획은 일회용·짧게")
> - **테스트 케이스 섹션**을 통해 TDD 강제 — 구현 전에 테스트 케이스 명시
> - 30줄 미만의 작은 변경은 EXEC_PLAN 자체가 면제됨 (`enforce-plan.sh`)

## 1. 목표 (Goal)

친구 초대 링크 발급/조회/목록/폐기 API를 구현한다.
친구 요청 API가 이미 소비하는 `friend_invitations` 테이블을 실제 클라이언트가 생성·공유할 수 있게 연결한다.

## 2. 접근 (Approach)

- `friend/controller/InvitationController.kt`
  - `POST /invitations` 인증 필요, 201
  - `GET /invitations/{token}` 공개 조회, 200
  - `GET /invitations` 인증 필요, 활성 링크 목록
  - `DELETE /invitations/{id}` 인증 필요, 204
- `friend/service/InvitationService.kt`
  - `create(inviterId: Long): InvitationResult`
  - `getByToken(token: String): InvitationPreview`
  - `listActive(inviterId: Long): List<InvitationResult>`
  - `revoke(inviterId: Long, invitationId: Long)`
  - base62 8자 토큰 생성, 중복 시 재시도
  - 만료 15일, URL `https://kicklog.app/i/{token}`
- 기존 `FriendInvitation`/Repository 확장
  - `findById`, `findActiveByInviterId`, `existsByToken`
  - `revoke(now)` 도메인 메서드
- 보안 설정
  - `GET /invitations/{token}`만 `permitAll`
- 예외
  - `INVITATION_NOT_FOUND`, `INVITATION_NOT_OWNED`
  - 기존 `INVITATION_EXPIRED`, `INVITATION_REVOKED` 재사용
- DB 마이그레이션 없음
  - `friend_invitations` 테이블은 PR #7 `V6__friendships.sql`에서 생성 완료

## 3. 테스트 케이스 (Test Cases) — TDD 핵심

> **🔴 RED 먼저, 🟢 GREEN 다음, 🔵 REFACTOR 마지막**

### (3-A) 인수 시나리오 (Gherkin)

@friend @invitation
Feature: 친구 초대 링크 API
  Scenario: 로그인 사용자는 초대 링크를 생성하고 공개 조회할 수 있다 (Happy)
    Given 사용자 A가 로그인했다
    When A가 POST /invitations 요청을 보낸다
    Then 201 응답에 token, url, expiresAt, useCount가 있다
    When 비로그인 사용자가 GET /invitations/{token} 요청을 보낸다
    Then 200 응답에 inviter 미리보기와 valid=true가 있다

  Scenario: 초대 링크 소유자가 아니면 폐기할 수 없다 (Unhappy)
    Given 사용자 A가 초대 링크를 만들었다
    When 사용자 B가 DELETE /invitations/{id} 요청을 보낸다
    Then 403 INVITATION_NOT_OWNED 응답을 받는다

  Scenario: 폐기된 초대 링크는 공개 조회할 수 없다 (Unhappy)
    Given 사용자 A가 초대 링크를 만들고 폐기했다
    When 비로그인 사용자가 GET /invitations/{token} 요청을 보낸다
    Then 410 INVITATION_REVOKED 응답을 받는다

### (3-B) 유스케이스 / 단위 테스트 케이스

Happy Path
- [x] `InvitationService.create` — 8자 base62 토큰과 15일 만료 초대 생성
- [x] `InvitationService.getByToken` — 공개 미리보기 반환
- [x] `InvitationService.listActive` — 활성 링크만 반환
- [x] `InvitationService.revoke` — 소유자 링크 폐기

Unhappy Path
- [x] `InvitationService.getByToken` — 없는 token은 `INVITATION_NOT_FOUND`
- [x] `InvitationService.getByToken` — 만료 token은 `INVITATION_EXPIRED`
- [x] `InvitationService.getByToken` — 폐기 token은 `INVITATION_REVOKED`
- [x] `InvitationService.revoke` — 비소유자는 `INVITATION_NOT_OWNED`

## 4. 검증 (Verification)

### 자동 검증
- 백엔드: `cd backend && ./gradlew test`
- 백엔드: `cd backend && ./gradlew compileKotlin`
- 백엔드: `cd backend && ./gradlew check`
- 결과: 세 명령 모두 통과. `./gradlew check --rerun-tasks`에서 PostgreSQL Testcontainers Flyway `V1`~`V6` 적용도 통과.

### 시나리오 검증 (수동)
- 로그인 사용자가 초대 링크를 만들고, 비로그인 상태에서 token 조회가 가능하다.
- 다른 사용자는 초대 링크를 폐기할 수 없다.
- 폐기/만료된 링크는 수락 화면 미리보기에서 거부된다.

### 커버리지
- Controller 인수 테스트 + Service 단위 테스트로 주요 Happy/Unhappy 분기 커버

---

## (Optional) 위험도 / 롤백

Risk = Caution

새 API 추가이며 DB 마이그레이션은 없다. 롤백은 PR revert로 처리한다.

## (Optional) 후속 / 관련 이슈

친구 경기/시즌 read-only API에서 `FriendshipAuthorizer`를 추가한다.

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
