# EXEC_PLAN — p1-display-name-unique

| 항목 | 값 |
|---|---|
| Task | p1-display-name-unique |
| Type | feature |
| Branch | feature/p1-display-name-unique |
| Worktree | /Users/opix/Developer/kicklog/.worktrees/p1-display-name-unique |
| Port | 9000 |
| 생성 시각 | 2026-05-28 |
| 상태 | `done` (구현·검증·리뷰 완료) |
| 개발 방식 | **TDD (Red → Green → Refactor)** |

---

## 1. 목표 (Goal)

P1 묶음 (#5 + #4) — 닉네임 유일 식별자 정책 도입 + 초대 링크 도메인 폐기.

- **#5**: `users.display_name` 을 활성 사용자 사이에서 unique 로 강제. 닉네임 검색만으로 친구 식별 가능 → 초대 링크 불필요.
- **#4**: 초대 링크 도메인 통째 폐기. #5 결정의 자동 따라옴 — 백엔드 7개 클래스 + iOS 3개 파일 제거.
- TestFlight 베타 사용자가 본인 / 누나뿐이라 데이터 마이그레이션 충돌 없음.

## 2. 접근 (Approach)

### 2-A. 백엔드 #5 — 닉네임 unique

| 변경 대상 | 변경 내용 |
|---|---|
| `db/migration/V12__users_display_name_unique.sql` | **신규** — `CREATE UNIQUE INDEX uq_users_display_name_active ON users (display_name) WHERE deleted_at IS NULL` (탈퇴자 닉네임 재사용 허용) |
| `common/exception/ErrorCode.kt` | 추가: `DISPLAY_NAME_DUPLICATE(CONFLICT, "이미 사용 중인 닉네임입니다")` |
| `user/entity/User.kt` | `User.create(displayName, email)` 에서 `displayName.trim()` 적용 |
| `user/service/UserService.kt` | `updateMe(userId, displayName)` 에 중복 검사 추가 — 본인 현재 닉네임과 동일하면 skip, 아니면 `userStore.findActiveByDisplayName(...)` 조회 + 충돌 시 `DISPLAY_NAME_DUPLICATE` throw. `DataIntegrityViolationException` 캐치해 race condition 대응 |
| `user/service/UserService.kt` | **신규** `checkDisplayName(userId, displayName)` — 현재 본인 닉네임과 동일 또는 미사용이면 `available=true` |
| `user/controller/UserController.kt` | **신규 endpoint** `GET /users/check-display-name?displayName=...` 🔒 — `@NotBlank @Size(1,50)` 검증 |
| `user/dto/DisplayNameCheckResponse.kt` | **신규** `data class DisplayNameCheckResponse(val available: Boolean)` |
| `user/repository/UserStore.kt` / `JpaUserStore.kt` | `findActiveByDisplayName(displayName: String): User?` 추가 — `WHERE display_name = ? AND deleted_at IS NULL` |
| `auth/service/AuthService.kt` | 회원가입 시 자동 suffix — `User.create(displayName, email)` 저장 시 `DataIntegrityViolationException` 캐치 → `${displayName}-${randomHex4()}` 로 최대 5회 재시도 → 그래도 실패면 `INTERNAL_ERROR` |
| `auth/service/AuthService.kt` | `randomHex4()` private helper (4자 hex, `SecureRandom`) |

### 2-B. 백엔드 #4 — 초대 링크 도메인 폐기

| 변경 대상 | 변경 내용 |
|---|---|
| `db/migration/V13__drop_friend_invitations.sql` | **신규** — `DROP TABLE friend_invitations` |
| `friend/entity/FriendInvitation.kt` | **제거** |
| `friend/repository/FriendInvitationStore.kt` | **제거** |
| `friend/repository/JpaFriendInvitationStore.kt` | **제거** |
| `friend/repository/FriendInvitationRepository.kt` | **제거** |
| `friend/service/InvitationService.kt` | **제거** |
| `friend/service/InvitationProperties.kt` | **제거** |
| `friend/service/InvitationTokenGenerator.kt` | **제거** |
| `friend/controller/InvitationController.kt` | **제거** |
| `friend/dto/InvitationDtos.kt` | **제거** |
| `friend/service/FriendshipService.kt` | `CreateFriendshipCommand.token` 필드 제거. `request` 의 token 분기 + `resolveInvitation` 메서드 제거. `targetUserId` 단독. 생성자에서 `invitationRepository` 의존 제거 |
| `friend/dto/FriendshipDtos.kt` | `CreateFriendshipRequest.token` 필드 제거 (있다면) |
| `common/exception/ErrorCode.kt` | 제거: `INVITATION_NOT_FOUND` / `INVITATION_NOT_OWNED` / `INVITATION_EXPIRED` / `INVITATION_REVOKED`. `FRIEND_INVALID_REQUEST` 메시지 갱신 ("targetUserId 는 필수입니다") |

### 2-C. iOS #5 — 닉네임 수정 UX

| 변경 대상 | 변경 내용 |
|---|---|
| `Networking/DTO/AuthDTO.swift` 또는 신규 `UserDTO.swift` | `struct DisplayNameCheckResponse: Decodable { let available: Bool }` |
| `Services/UserService.swift` | `func checkDisplayName(_ displayName: String) async throws -> DisplayNameCheckResponse` |
| `Screens/SettingsScreen.swift` displayNameEditor | State: `enum CheckState { case idle, checking, available, duplicate, error(String) }`. `.onChange(of: displayNameDraft)` 에서 Task launched 300ms debounce → check 호출. 라벨 ✓/⚠/네트워크 에러 표시. 저장 disabled 조건 `checkState != .available && draft != me.displayName` |
| 본인 현재 닉네임과 동일 입력 | check skip + `CheckState.idle` 유지. 저장 버튼은 disabled (no-op) |

### 2-D. iOS #4 — invitation 도메인 제거

| 변경 대상 | 변경 내용 |
|---|---|
| `Networking/DTO/InvitationDTO.swift` | **제거** |
| `Services/InvitationService.swift` | **제거** |
| `Models/Domain.swift` | `FriendInvitation` 관련 SwiftData 모델 제거 (있다면) — 검색해서 정리 |
| `Screens/AddFriendSheet.swift` | invitation 관련 state·section·콜백 통째 제거. **사용자 검색 입력 + 결과만 남김** (검색 비어있을 때 invitation 자리에는 "닉네임으로 친구를 찾아보세요" 안내) |

### 2-E. Docs

| 변경 대상 | 변경 내용 |
|---|---|
| `docs/PRD.md` line 73-75 | 친구 추가 영역 — 초대 링크 메인 → "닉네임 검색만". v1 단순화 명시 |
| `docs/adr/0003-data-model-and-api.md` | V12, V13 history note + friend_invitations 테이블 정의 deprecated 표기 + Friends endpoint 표 갱신 (invitation 5개 endpoint 제거) |
| `docs/spec/api-spec.md` | §2 Users 추가: `GET /users/check-display-name`. §4 Invitations 섹션 통째 제거. §3.1 친구 추가 요청 본문 — `token` 필드 제거 |
| `docs/spec/diagram.md` | ERD 에서 `friend_invitations` 테이블 행 제거 (있다면) |

**계약 (양보 불가)**:
- `users.display_name` UNIQUE INDEX 는 **활성 사용자만** (`WHERE deleted_at IS NULL`) — 탈퇴자 닉네임 재사용 가능
- 본인 현재 닉네임과 동일한 PATCH 는 200 (no-op 또는 trim 만 적용) — false positive 방지
- 회원가입 시 충돌은 **사용자에게 알리지 않고 자동 suffix** — onboarding 없는 현 상태에서 가입 흐름 단절 회피
- `GET /users/check-display-name` 은 **자기 자신 비교 포함** — 본인 닉네임 입력 시 `available=true`
- iOS debounce 는 **300ms**, 입력 빈 문자열일 땐 check 호출 안 함

## 3. 테스트 케이스 (Test Cases) — ATDD 1차

### (3-A) 인수 시나리오 (Gherkin)

```gherkin
@user @display-name @smoke
Feature: 닉네임 unique + 중복 확인 API
  Scenario: 사용 가능한 닉네임으로 변경 (Happy)
    Given 로그인한 사용자 "u1" (displayName="홍길동")
    And "홍길순" 닉네임은 사용 중이 아님
    When PATCH /users/me 에 { "displayName": "홍길순" } 본문으로 요청
    Then 200 + displayName="홍길순"

  Scenario: 본인 현재 닉네임으로 PATCH → 200 (no-op)
    Given 로그인한 사용자 "u1" (displayName="홍길동")
    When PATCH /users/me 에 { "displayName": "홍길동" } 본문으로 요청
    Then 200 + displayName="홍길동" (중복 검사 skip)

  @edge-case
  Scenario: 이미 사용 중인 닉네임으로 변경 → 409 (Unhappy)
    Given 로그인한 사용자 "u1" (displayName="홍길동")
    And 다른 활성 사용자가 "박수비" 닉네임 사용 중
    When PATCH /users/me 에 { "displayName": "박수비" } 본문으로 요청
    Then 409 + code="DISPLAY_NAME_DUPLICATE"

  Scenario: 탈퇴자 닉네임 재사용 허용
    Given 탈퇴 처리된 사용자 "deleted-user" (displayName="박수비")
    And 로그인한 사용자 "u1" (displayName="홍길동")
    When PATCH /users/me 에 { "displayName": "박수비" } 본문으로 요청
    Then 200 + displayName="박수비"

  Scenario: 미사용 닉네임 가용 확인 (Happy)
    Given 로그인한 사용자 "u1"
    And "축구왕" 닉네임은 사용 중이 아님
    When GET /users/check-display-name?displayName=축구왕 요청
    Then 200 + available=true

  Scenario: 본인 현재 닉네임 가용 확인 → true
    Given 로그인한 사용자 "u1" (displayName="홍길동")
    When GET /users/check-display-name?displayName=홍길동 요청
    Then 200 + available=true

  @edge-case
  Scenario: 사용 중 닉네임 가용 확인
    Given 로그인한 사용자 "u1"
    And 다른 활성 사용자가 "박수비" 닉네임 사용 중
    When GET /users/check-display-name?displayName=박수비 요청
    Then 200 + available=false

  @edge-case
  Scenario: displayName 파라미터 누락 → 400
    Given 로그인한 사용자 "u1"
    When GET /users/check-display-name 요청 (파라미터 없음)
    Then 400 + code="VALIDATION_FAILED"

@auth @display-name
Feature: 회원가입 시 닉네임 충돌 자동 suffix
  Scenario: 같은 displayName 이미 존재하면 자동 suffix
    Given 활성 사용자가 "축구왕" 닉네임 사용 중
    When 신규 카카오 사용자가 displayNameHint="축구왕" 으로 첫 로그인
    Then 가입 성공 + 신규 user.displayName 이 "축구왕-XXXX" 형태 (X = hex)

  Scenario: 충돌 없으면 hint 그대로 사용
    Given "축구왕" 닉네임 미사용
    When 신규 카카오 사용자가 displayNameHint="축구왕" 으로 첫 로그인
    Then 가입 성공 + user.displayName="축구왕"

@friend @smoke @regression
Feature: 친구 요청 — token 경로 폐기 회귀
  Scenario: targetUserId 경로 정상
    Given 사용자 "me" 와 "other" 가 친구 아님
    When POST /friendships { "targetUserId": <other.id> }
    Then 201 + friendshipId 발급 + pending 상태

  @edge-case
  Scenario: token 필드는 응답에 영향 없음 (옛 클라 호환)
    Given 사용자 "me"
    When POST /friendships { "targetUserId": <other.id>, "token": "garbage" } (옛 iOS 호환)
    Then 201 (token 무시 — Jackson ignoreUnknown 의존)

  @edge-case
  Scenario: POST /invitations 엔드포인트 자체 제거 — 404
    When POST /invitations 호출
    Then 404 (해당 컨트롤러 클래스 자체 제거 확인)
```

### (3-B) 유스케이스 / 단위 테스트 케이스

- `UserService.updateMe` — 본인 닉네임 동일 / 미사용 / 사용 중 3분기 단위
- `UserService.checkDisplayName` — 본인 동일 / 미사용 / 사용 중 / 탈퇴자 닉네임 단위
- `AuthService.signIn` 충돌 자동 suffix — Mock UserStore 가 첫 시도 충돌 + 두 번째 성공 케이스
- `UserStore.findActiveByDisplayName` — 활성/탈퇴 사용자 분리 단위
- `User.create(displayName, email)` — displayName 앞뒤 공백 trim 단위
- `FriendshipService.request` — token 분기 제거 후 targetUserId 단독 호출 단위

### 테스트 작성자 (자동 위임)
- 백엔드 → `backend-test-writer` agent
- iOS → 본 하네스 대상 아님 (사용자가 Xcode 에서 직접)

## 4. 검증 (Verification)

### 자동 검증
- 백엔드: `cd backend && ./gradlew check`
- 마이그레이션: Testcontainers 부팅 시 V12, V13 적용 + 부팅 성공
- iOS: 자동 검증 없음 (사용자가 Xcode 에서 빌드)

### 시나리오 검증 (수동)
- (#5 Backend) curl 로 `GET /users/check-display-name?displayName=홍길동` Bearer 토큰 헤더 — `{ available: bool }`
- (#5 Backend) curl 로 누나·본인 닉네임 동일하게 PATCH 시도 → 409
- (#5 iOS) 설정 → 이름 수정 → "누나" 입력 후 300ms 대기 → ⚠ 라벨 표시 + 저장 disabled
- (#5 iOS) 설정 → 이름 수정 → "새이름" 입력 → ✓ 라벨 + 저장 활성 → 저장 후 me.displayName 갱신
- (#4) AddFriendSheet 에 초대 링크 영역 없음 + 검색 입력 + 결과 클릭 → 친구 요청 정상 동작

### 커버리지
- 새 코드 커버리지 70% 이상

---

## (Optional) 위험도 / 롤백

**Risk = Risky** — V12 UNIQUE INDEX + V13 DROP TABLE + Breaking API.

**롤백 전략**:
- V12 다운: `DROP INDEX uq_users_display_name_active`
- V13 다운: 베타라 데이터 손실 무시 가능. 운영에서는 백업으로 복원.
- 옛 iOS 빌드의 `POST /invitations` 호출 → 404. 핫픽스 빌드 배포 권장.

## (Optional) 후속 / 관련 이슈

- P2: #6 앱 아이콘 / #7 온보딩
- P3: #10 카카오맵 운동장

## (Optional) 학습 기록

작업 종료 시 self-heal / Critical / 누락 테스트 기록.
