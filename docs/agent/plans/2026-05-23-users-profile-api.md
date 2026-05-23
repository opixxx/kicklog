# EXEC_PLAN — users-profile-api

| 항목 | 값 |
|---|---|
| Task | users-profile-api |
| Type | feature |
| Branch | feature/users-profile-api |
| Worktree | /Users/opix/Developer/kicklog/.worktrees/users-profile-api |
| Port | 9000 |
| 생성 시각 | 2026-05-23 18:37 |
| 상태 | `draft` (작성 중) |
| 개발 방식 | **TDD (Red → Green → Refactor)** |

---

## 1. 목표 (Goal)

`api-spec.md` §2.2~2.5 의 Users 도메인 endpoint 4개를 구현해 사용자 라이프사이클(프로필 수정 / soft delete / 복구 / 검색)을 완성한다.
함께 `USER_DELETED(410)` 차단을 모든 보호 endpoint 에 일관 적용하고, 30일 grace 후 hard delete 하는 `@Scheduled` cron 도 본 PR 에 포함한다 (ADR-0003 D8).
Friends 도메인이 `GET /users/search` 에 의존하므로 이번 PR 이 그 선행 작업이다.

## 2. 접근 (Approach)

### 2.1 신규 endpoint

| Method | URL | 동작 | 권한 |
|---|---|---|---|
| `PATCH` | `/users/me` | displayName / hideHeartRate 부분 수정 | 🔒 |
| `DELETE` | `/users/me` | soft delete (deleted_at = now) + 모든 refresh token revoke | 🔒 |
| `POST` | `/users/me/cancel-deletion` | deleted_at = NULL (deleted 사용자도 통과) | 🔒, deleted 허용 |
| `GET` | `/users/search?q=&limit=` | display_name ILIKE 부분 일치, 본인 제외, 최대 50 clamp | 🔒 |

### 2.2 변경 / 신규 파일

**user 패키지**:
- `user/entity/User.kt` — `updateProfile(name, hide)`, `markDeleted(now)`, `cancelDeletion()` 도메인 메서드 추가
- `user/dto/UpdateMeRequest.kt` (신규) — `displayName: String?`, `hideHeartRate: Boolean?` + `@AssertTrue` 로 "최소 1개 필드" 검증
- `user/dto/UserSearchResponse.kt` (신규) — `users: List<Item>(id, displayName)` (email 미포함)
- `user/service/UserService.kt` (신규) — updateMe / softDelete / cancelDeletion / search / purgeExpired
- `user/repository/UserStore.kt` + `JpaUserStore.kt` + `UserRepository.kt` — search·findExpiredDeleted·delete 메서드 추가
- `user/controller/UserController.kt` — endpoint 4개 추가
- `user/scheduler/UserPurgeScheduler.kt` (신규) — `@Scheduled(cron = "0 0 4 * * *")` purgeDeletedUsers

**common / config**:
- `common/exception/ErrorCode.kt` — `USER_DELETED(410)`, `USER_NOT_DELETING(409)` 추가 (USER_PURGED 는 현재 발생 경로 없음 — 별도 PR 에서 hard delete 직후 PURGED 응답 분기 가능)
- `config/SecurityConfig.kt` 또는 `JwtAuthenticationFilter.kt` — deleted 사용자 차단 로직 추가 (단, `/users/me/cancel-deletion` 만 예외)
- `KicklogApplication.kt` 또는 별도 `SchedulingConfig.kt` — `@EnableScheduling` 활성화

### 2.3 양보 불가 규칙

1. **트랜잭션 경계**: 변경(write) 메서드는 `@Transactional`, 조회는 `readOnly = true`. UserService.softDelete 는 RefreshTokenStore 변경까지 한 트랜잭션.
2. **권한**: 모든 endpoint 는 `@AuthenticationPrincipal KickLogPrincipal` 사용. `/users/me/cancel-deletion` 만 deleted 통과.
3. **DTO 흐름**: Request → (Command 없이 직접 service 호출 OK — 매개변수가 2~3개) → Response 변환. Entity 직접 노출 금지.
4. **검색 limit clamp**: `min(max(limit, 1), 50)` — 50 초과면 silently 50 으로.
5. **검색 자기 제외**: WHERE 절에 `id != :selfId`.
6. **deleted 사용자 차단**: filter 단에서 `UserStore.findById(...)?.isDeleted == true && path != "/users/me/cancel-deletion"` → `USER_DELETED(410)` 응답. SecurityContext clear 가 아닌 명시적 응답.
7. **DB 변경 없음**: `deleted_at` 컬럼 이미 V2 에서 존재. **마이그레이션 불필요**.

### 2.4 외부 의존

- 없음 (Kakao / Apple 호출 없음, DB only).

## 3. 테스트 케이스 (Test Cases) — TDD 핵심

### (3-A) 인수 시나리오 (Gherkin) → `UserProfileAcceptanceTest.kt`

기존 프로젝트는 Cucumber 미도입 — `@SpringBootTest + MockMvc` 로 동등하게 표현. 시나리오 1개 = 테스트 메서드 1개.

```gherkin
@user @smoke
Feature: 내 프로필 수정 / 삭제 / 복구 / 검색

  Scenario: PATCH displayName 만 변경 (Happy)
    Given 인증된 사용자 id=1, displayName="김조축"
    When PATCH /users/me { "displayName": "김캡틴" }
    Then 200 + displayName="김캡틴", hideHeartRate=false (변경 없음)

  Scenario: PATCH hideHeartRate 만 변경 (Happy)
    Given 인증된 사용자 id=1
    When PATCH /users/me { "hideHeartRate": true }
    Then 200 + hideHeartRate=true

  @edge-case
  Scenario: PATCH 둘 다 누락 → 400 VALIDATION_FAILED (Unhappy)
    When PATCH /users/me { } → 400

  @edge-case
  Scenario: PATCH displayName 51자 → 400 VALIDATION_FAILED (Unhappy)

  Scenario: DELETE /users/me (Happy)
    Given 인증된 사용자 + 활성 refresh token 2개
    When DELETE /users/me
    Then 204 + user.deletedAt != null + refresh token 모두 revoke

  Scenario: cancel-deletion 정상 복구 (Happy)
    Given deleted_at 이 설정된 사용자
    When POST /users/me/cancel-deletion
    Then 200 + deletedAt == null + UserResponse

  @edge-case
  Scenario: cancel-deletion 미삭제 상태 → 409 USER_NOT_DELETING (Unhappy)

  @edge-case
  Scenario: deleted 사용자가 GET /users/me 호출 → 410 USER_DELETED (Unhappy)

  Scenario: GET /users/search?q=수비 (Happy)
    Given users: id=2 "박수비", id=3 "박공격", id=4 "이수비", id=1 "수비왕(나)"
    When 인증 id=1 로 GET /users/search?q=수비
    Then 200 + 2명 (id=2, id=4) + 본인 제외 + email 없음

  @edge-case
  Scenario: GET /users/search?q=&limit=100 → limit 50 으로 clamp (Edge)

  @edge-case
  Scenario: deleted 사용자는 검색 결과에서 제외 (Edge)
```

### (3-B) 유스케이스 / 단위 테스트 케이스 → `UserServiceTest.kt`

`InMemoryUserRepository` + `InMemoryRefreshTokenRepository` 활용:

- `UserService.updateMe(userId, displayName=null, hideHeartRate=true)` — null 무시, hideHeartRate 만 갱신, updated_at 갱신
- `UserService.updateMe` — 두 필드 모두 null 이면 throw VALIDATION_FAILED (Service 도 보조 검증)
- `UserService.softDelete(userId)` — deleted_at 설정 + RefreshTokenStore.findActiveByUserId 의 모든 토큰 revoke
- `UserService.cancelDeletion(userId)` — deleted 면 deletedAt=null, 정상 사용자면 USER_NOT_DELETING throw
- `UserService.search(q, limit, selfId)` — 본인 제외 + deleted 제외 + ILIKE %q% + limit clamp(1..50)
- `UserService.purgeExpired(now)` — `deleted_at < now - 30d` 인 사용자 hard delete (CASCADE 의존, repository.delete 호출만 검증)
- `UserPurgeScheduler.purgeDeletedUsers()` — `Clock` 주입해서 cutoff 계산 검증 (별도 SchedulerTest)

### 테스트 작성자 (자동 위임)
- 백엔드 → `backend-test-writer` agent (MockMvc Acceptance + InMemory Service 단위)

## 4. 검증 (Verification)

### 자동 검증
```bash
cd backend
./gradlew compileKotlin   # 컴파일 게이트
./gradlew test            # 전체 테스트
./gradlew check           # + 정적 검사
```

### 시나리오 검증 (manual smoke, 선택)
```bash
# 로그인 → access token 획득 후
curl -X PATCH http://localhost:8080/users/me \
  -H "Authorization: Bearer $T" -H "Content-Type: application/json" \
  -d '{"displayName":"김캡틴"}'

curl -X DELETE http://localhost:8080/users/me -H "Authorization: Bearer $T"
# 같은 토큰으로 다시 호출 시 410 USER_DELETED

curl -X POST http://localhost:8080/users/me/cancel-deletion -H "Authorization: Bearer $T"
# 200, deletedAt: null

curl "http://localhost:8080/users/search?q=수비&limit=10" -H "Authorization: Bearer $T"
```

### 커버리지
- 새 코드 신규 클래스 (UserService, UserPurgeScheduler) — Service 단위 테스트로 분기 커버. Acceptance 로 HTTP→Service→DB 경로 1회 커버.

---

## (Optional) 위험도 / 롤백

**Risk = Caution**.
- DB 마이그레이션 없음 (`deleted_at` 컬럼 이미 존재).
- @EnableScheduling 활성화는 신규 — 다른 도메인에서 추후 추가될 @Scheduled 와의 충돌 없음 (현재 0건).
- USER_DELETED 차단을 모든 보호 endpoint 에 도입 — 기존 venue/match/place 의 인증 흐름에 영향. 단, 정상 사용자는 영향 없고, deleted 사용자는 이미 사용 불가가 의도된 상태.
- Rollback: 단순 revert. 마이그레이션 없음.

## (Optional) 후속 / 관련 이슈

- `USER_PURGED(410)`: 현재 hard delete 가 진행되면 row 가 없어지므로 `USER_NOT_FOUND` 와 구분 불가. iOS 클라이언트가 deleted_at 추적까지 가져갈지에 따라 별도 PR.
- 디바이스별 세션 관리 (ADR-0003 D7.1 v1.1+).
- Friends 도메인 (`GET /users/search` 의 최대 사용처).

## (Optional) 학습 기록

추후 self-heal / Critical 리뷰 발생 시 기록.
