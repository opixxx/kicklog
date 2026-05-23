# EXEC_PLAN — kakao-login

| 항목 | 값 |
|---|---|
| Task | kakao-login |
| Type | feature |
| Branch | feature-kakao-login |
| Worktree | /Users/opix/Developer/kicklog/.worktrees/kakao-login |
| 상태 | `done` |
| 개발 방식 | **TDD (Red → Green → Refactor)** |

## 1. 목표 (Goal)

Kakao access token을 백엔드에서 검증하고, 신규/기존 사용자에게 KickLog JWT access token과 refresh token을 발급한다. API 계약은 `POST /auth/kakao/signin`, `POST /auth/refresh`를 우선 구현하며 iOS는 이 토큰만 사용한다.

## 2. 접근 (Approach)

- `auth/controller/AuthController`: `POST /auth/kakao/signin`, `POST /auth/refresh` 공개 엔드포인트 추가.
- `auth/service/KakaoOAuthGateway`: Kakao `/v2/user/me` 호출을 인터페이스로 분리해 테스트에서 대체한다.
- `auth/service/AuthService`: Kakao 사용자 조회는 트랜잭션 밖에서 수행하고, `OAuthIdentity(provider=KAKAO, providerUserId=id)` 기준으로 사용자 생성/조회 후 JWT 발급.
- `common/security/JwtTokenProvider`, `JwtAuthenticationFilter`: HS256 access/refresh token 발급과 보호 API 인증 필터 추가.
- `V2__auth_kakao_jwt.sql`: `oauth_identities`, `refresh_tokens`, `users.email/deleted_at` 추가.
- `SecurityConfig`: `/auth/kakao/signin`, `/auth/refresh`, actuator health/info만 permitAll.

## 3. 테스트 케이스 (Test Cases)

### (3-A) 인수 시나리오 (Gherkin)

```gherkin
@auth @smoke
Feature: 카카오 로그인
  Scenario: 신규 카카오 사용자가 로그인한다
    Given Kakao가 id "12345", nickname "김조축", email "kakao@example.com"을 반환한다
    When POST /auth/kakao/signin 요청을 보낸다
    Then 200 응답과 accessToken, refreshToken, user.displayName "김조축"을 받는다

  Scenario: 유효하지 않은 카카오 토큰으로 로그인한다
    Given Kakao가 토큰 오류를 반환한다
    When POST /auth/kakao/signin 요청을 보낸다
    Then 401 AUTH_INVALID_KAKAO_TOKEN 응답을 받는다
```

### (3-B) 유스케이스 / 단위 테스트 케이스

- Happy: 동일 Kakao id로 두 번 로그인하면 `users`와 `oauth_identities`가 중복 생성되지 않는다.
- Happy: refresh token으로 새 access token을 발급하고 refresh token은 그대로 반환한다.
- Unhappy: 빈 `kakaoAccessToken` 요청은 `400 VALIDATION_FAILED`를 반환한다.
- Unhappy: Kakao 5xx/네트워크 실패는 `502 EXTERNAL_KAKAO_UNAVAILABLE`로 매핑한다.

## 4. 검증 (Verification)

- `cd backend && ./gradlew test`
- `cd backend && ./gradlew compileKotlin`
- `cd backend && ./gradlew check`

## (Optional) 위험도 / 롤백

Risk = Caution. DB 마이그레이션이 포함되며 롤백은 `oauth_identities`, `refresh_tokens` 테이블 제거 및 `users.email`, `users.deleted_at` 컬럼 제거다.
