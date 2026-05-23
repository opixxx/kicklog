# EXEC_PLAN — login-auth-complete

| 항목 | 값 |
|---|---|
| Task | login-auth-complete |
| Type | feature |
| Branch | feature/login-auth-complete |
| Worktree | /Users/opix/Developer/kicklog/.worktrees/login-auth-complete |
| Port | 9000 |
| 생성 시각 | 2026-05-23 11:06 |
| 상태 | `done` |
| 개발 방식 | **TDD (Red → Green → Refactor)** |

---

> **단순화 + TDD 원칙**:
> - 본 템플릿은 GearShow의 8섹션을 KickLog용 **4섹션 + optional**로 축소 (Ralph: "계획은 일회용·짧게")
> - **테스트 케이스 섹션**을 통해 TDD 강제 — 구현 전에 테스트 케이스 명시
> - 30줄 미만의 작은 변경은 EXEC_PLAN 자체가 면제됨 (`enforce-plan.sh`)

## 1. 목표 (Goal)

KickLog 백엔드의 로그인 관련 기능을 한 PR에서 완성한다. Apple/Kakao OAuth 로그인으로 내부 JWT 세션을 만들고, Access 15분 + Refresh 30일 + refresh rotation 정책으로 갱신·로그아웃·보호 API 인증까지 구현한다.

## 2. 접근 (Approach)

- 문서
  - `docs/PRD.md`, `docs/adr/0003-data-model-and-api.md`, `docs/architecture/auth.md`, `docs/spec/api-spec.md`, `docs/spec/diagram.md`, `docs/spec/test-strategy.md`
  - 토큰 정책을 Access 15분 + Refresh 30일 + refresh rotation으로 갱신한다.
- DB
  - `V2__auth_sessions.sql`: placeholder `users`를 auth 스펙 구조로 재정의하고 `oauth_identities`, `refresh_tokens`를 추가한다.
  - `refresh_tokens.jti`는 UUID PK, `rotated_to_jti`, `revoked_at`, `last_used_at`를 관리한다.
- API
  - `POST /auth/apple/signin`
  - `POST /auth/kakao/signin`
  - `POST /auth/refresh`
  - `POST /auth/logout`
  - `POST /auth/logout/this-device`
  - `GET /users/me`
- 구현 패키지
  - `auth/controller`, `auth/service`, `auth/repository`, `auth/entity`, `auth/dto`
  - `user/controller`, `user/entity`, `user/repository`, `user/dto`
  - `common/security`, `common/exception`, `common/config`
- 핵심 규칙
  - OAuth provider token은 로그인 시 1회만 검증하고 이후 내부 JWT만 사용한다.
  - Access token은 DB에 저장하지 않는다.
  - Refresh token은 DB에 저장하고 `/auth/refresh`마다 기존 JTI를 revoke한 뒤 새 JTI를 발급한다.
  - 이미 revoke된 refresh token 재사용이 감지되면 해당 사용자의 활성 refresh token을 모두 revoke한다.
  - Kakao/Apple 외부 API 호출은 트랜잭션 밖에서 수행한다.
  - 토큰·provider user id는 `UserResponse`에 노출하지 않는다.

## 3. 테스트 케이스 (Test Cases) — TDD 핵심

> **🔴 RED 먼저, 🟢 GREEN 다음, 🔵 REFACTOR 마지막**

### (3-A) 인수 시나리오 (Gherkin)
@auth @smoke
Feature: 로그인과 JWT 세션
  Scenario: 카카오 신규 사용자가 로그인하면 내부 JWT 세션이 생성된다
    Given 유효한 카카오 access token이 있다
    When /auth/kakao/signin 으로 로그인 요청한다
    Then 200 응답과 accessToken, refreshToken, user가 반환된다
    And refresh token은 DB에 활성 상태로 저장된다

  Scenario: refresh token으로 토큰을 갱신하면 refresh token이 rotation 된다
    Given 로그인으로 발급된 refresh token이 있다
    When /auth/refresh 로 갱신 요청한다
    Then 200 응답과 새로운 accessToken, refreshToken이 반환된다
    And 기존 refresh token은 revoke되고 새 refresh token만 활성 상태다

  Scenario: 폐기된 refresh token을 재사용하면 모든 세션이 폐기된다
    Given 이미 rotation으로 폐기된 refresh token이 있다
    When /auth/refresh 로 갱신 요청한다
    Then 401 AUTH_REFRESH_REUSED 응답이 반환된다
    And 해당 사용자의 모든 refresh token이 revoke된다

  Scenario: 로그아웃하면 refresh token이 폐기된다
    Given 로그인한 사용자가 있다
    When /auth/logout/this-device 로 로그아웃 요청한다
    Then 204 응답이 반환된다
    And 해당 refresh token은 revoke된다

### (3-B) 유스케이스 / 단위 테스트 케이스
- `JwtTokenProvider`는 access 15분, refresh 30일, type claim, refresh JTI를 발급·검증한다.
- `AuthService.signInWithKakao`는 신규/기존 OAuth identity를 구분하고 사용자와 refresh token을 저장한다.
- `AuthService.refresh`는 rotation을 수행하고 revoked/expired/reused refresh token을 거부한다.
- `AuthService.logout`은 전체 세션을 revoke하고 `logoutThisDevice`는 요청 JTI만 revoke한다.
- `JwtAuthenticationFilter`는 `/auth/**`, actuator를 제외한 보호 API에 인증 principal을 주입한다.
- `GET /users/me`는 access token 사용자만 조회하고 soft deleted 사용자는 거부한다.

## 4. 검증 (Verification)

### 자동 검증
- 백엔드: `cd backend && ./gradlew check`
- iOS: 자동 검증 없음 (사용자가 Xcode 에서 수동 빌드)

### 시나리오 검증 (수동)
- 카카오 로그인 응답의 refresh token으로 `/auth/refresh`를 호출하면 새 refresh token이 반환된다.
- 이전 refresh token으로 다시 `/auth/refresh`를 호출하면 401과 함께 활성 세션이 폐기된다.
- access token으로 `/users/me` 호출 시 사용자 정보가 반환되고 토큰/provider id는 노출되지 않는다.

### 커버리지
- 인증 핵심 서비스와 JWT provider는 단위 테스트로 검증한다.

---

## (Optional) 위험도 / 롤백

Risk = Caution. 기존 `V1`이 placeholder 사용자 스키마이므로 `V2`에서 auth 스키마로 재정의한다. 운영 데이터가 생긴 뒤에는 destructive migration을 금지하고 별도 데이터 이전 마이그레이션으로 전환해야 한다.

## (Optional) 후속 / 관련 이슈

- iOS Keychain 저장/자동 refresh/retry 연동은 사용자가 Xcode에서 별도 구현한다.
- v1.1에서 디바이스별 세션 관리 화면과 refresh reuse 알림을 검토한다.

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
7. PR 생성 (/pr-guide)
```

> 완료 시: `상태` 필드를 `done`으로 변경하고 PR 본문에 본 파일 링크 첨부.
