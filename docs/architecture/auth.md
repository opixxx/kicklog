# KickLog 인증 아키텍처

> 결정 근거는 ADR-0003 D7 / D7.1 / D8. 본 문서는 그 결정을 **코드 레벨로 어디에 어떻게 둘지** 정의한다.

---

## 한 줄 요약

**Apple Sign-In + Kakao Login → 우리 JWT (Access 1h + Refresh 90d) → Spring Security Filter 에서 검증.**

OAuth provider token 은 첫 가입·로그인 시 1회만 사용. 이후 모든 API 는 우리가 발급한 JWT 로만.

---

## 토큰 정책 (ADR-0003 D7.1)

| 토큰 | 수명 | 저장 | 갱신 |
|---|---|---|---|
| **Access Token** | 1h | iOS KeyChain | 매 요청 헤더 |
| **Refresh Token** | 90d | DB (`refresh_tokens` 테이블) + iOS KeyChain | `/auth/refresh` |

- Refresh token 은 **DB 에 저장**해서 강제 로그아웃·revoke 지원
- JTI(JWT ID) 를 PK 로 사용 → revoke 시 `revoked_at` 만 채움
- Access token 은 DB 비저장 (stateless)

### 클레임

| 클레임 | 의미 |
|---|---|
| `sub` | `users.id` (Long → String) |
| `iss` | `kicklog` |
| `aud` | `kicklog-ios` |
| `iat` | 발급 시각 |
| `exp` | 만료 시각 |
| `jti` | Refresh 만, UUID |
| `type` | `access` \| `refresh` |

### 서명
- HMAC-SHA256 (HS256), 시크릿은 **AWS Secrets Manager** (ADR-0006 D6)
- 로컬은 `application-local.yml` 에 dev 시크릿

---

## 패키지 배치

```
com.opixxx.kicklog/
├── auth/
│   ├── controller/AuthController.kt
│   ├── service/
│   │   ├── AuthService.kt                  # 핵심 오케스트레이션
│   │   ├── AppleIdentityVerifier.kt        # Apple JWKS 로 identityToken 검증
│   │   ├── KakaoOAuthClient.kt             # Kakao /v2/user/me 호출
│   │   └── RefreshTokenService.kt          # JTI 발급·검증·revoke
│   ├── repository/
│   │   ├── OAuthIdentityRepository.kt
│   │   └── RefreshTokenRepository.kt
│   ├── entity/
│   │   ├── OAuthIdentity.kt
│   │   └── RefreshToken.kt
│   └── dto/
│       ├── AppleSignInRequest.kt
│       ├── KakaoSignInRequest.kt
│       ├── RefreshRequest.kt
│       └── SignInResponse.kt
└── common/
    ├── security/
    │   ├── JwtTokenProvider.kt             # 발급·파싱·검증
    │   ├── JwtAuthenticationFilter.kt      # OncePerRequestFilter
    │   ├── KickLogPrincipal.kt             # SecurityContext 에 들어가는 객체
    │   └── PrincipalArgumentResolver.kt    # @CurrentUser 어노테이션 처리
    └── config/
        └── SecurityConfig.kt               # 현재 위치: backend/src/main/kotlin/com/opixxx/kicklog/config/SecurityConfig.kt → common/config/ 로 이동 권장
```

---

## Apple Sign-In 흐름

```
┌──────┐                  ┌────────┐                    ┌──────────┐
│ iOS  │                  │ Server │                    │ Apple    │
└───┬──┘                  └────┬───┘                    └────┬─────┘
    │                          │                             │
    │ ASAuthorizationApple...  │                             │
    │ → identityToken 받음     │                             │
    │                          │                             │
    │ POST /auth/apple/signin  │                             │
    │ { identityToken, name? } │                             │
    │─────────────────────────▶│                             │
    │                          │ JWKS 조회 (캐시)            │
    │                          │────────────────────────────▶│
    │                          │◀────────────────────────────│ 공개키
    │                          │ identityToken 검증          │
    │                          │ (kid·alg=RS256·iss·aud·exp) │
    │                          │                             │
    │                          │ SELECT oauth_identities     │
    │                          │ WHERE provider='apple'      │
    │                          │   AND provider_user_id=sub  │
    │                          │                             │
    │                          │ ─ 있음 → 기존 user_id       │
    │                          │ ─ 없음 → INSERT users       │
    │                          │           + oauth_identities│
    │                          │                             │
    │                          │ JWT 발급 (access + refresh) │
    │ { accessToken,           │ INSERT refresh_tokens       │
    │   refreshToken, user }   │                             │
    │◀─────────────────────────│                             │
```

### 검증 항목 (`AppleIdentityVerifier`)

```kotlin
class AppleIdentityVerifier(
    private val jwksProvider: AppleJwksProvider,    // 캐시된 공개키
) {
    fun verify(identityToken: String): AppleIdentity {
        val unverifiedJwt = JWT.decode(identityToken)
        val kid = unverifiedJwt.keyId
            ?: throw InvalidAppleTokenException("kid 누락")

        val publicKey = jwksProvider.getPublicKey(kid)
            ?: throw InvalidAppleTokenException("알 수 없는 kid: $kid")

        val verified = JWT.require(Algorithm.RSA256(publicKey, null))
            .withIssuer("https://appleid.apple.com")
            .withAudience(APPLE_CLIENT_ID)
            .build()
            .verify(identityToken)

        return AppleIdentity(
            sub = verified.subject,
            email = verified.getClaim("email").asString(),
        )
    }
}
```

JWKS 캐시: `https://appleid.apple.com/auth/keys` → 24h TTL.

---

## Kakao Login 흐름

```
┌──────┐                  ┌────────┐                    ┌──────────┐
│ iOS  │                  │ Server │                    │ Kakao    │
└───┬──┘                  └────┬───┘                    └────┬─────┘
    │                          │                             │
    │ KakaoOpenSDK             │                             │
    │ loginWithKakaoTalk       │                             │
    │ → kakaoAccessToken       │                             │
    │                          │                             │
    │ POST /auth/kakao/signin  │                             │
    │ { kakaoAccessToken }     │                             │
    │─────────────────────────▶│                             │
    │                          │ GET /v2/user/me             │
    │                          │ Authorization: Bearer ...   │
    │                          │────────────────────────────▶│
    │                          │◀────────────────────────────│ { id, kakao_account }
    │                          │                             │
    │                          │ provider_user_id = id       │
    │                          │ (이하 Apple 과 동일 흐름)   │
    │                          │                             │
    │ { accessToken,           │                             │
    │   refreshToken, user }   │                             │
    │◀─────────────────────────│                             │
```

`KakaoOAuthClient`:
```kotlin
class KakaoOAuthClient(
    private val webClient: WebClient,
) {
    fun fetchUserInfo(kakaoAccessToken: String): KakaoUserInfo {
        return webClient.get()
            .uri("https://kapi.kakao.com/v2/user/me")
            .header(HttpHeaders.AUTHORIZATION, "Bearer $kakaoAccessToken")
            .retrieve()
            .onStatus({ it.is4xxClientError }) {
                Mono.error(InvalidKakaoTokenException("Kakao 토큰 검증 실패"))
            }
            .bodyToMono<KakaoUserInfo>()
            .timeout(Duration.ofSeconds(5))
            .block() ?: throw ExternalKakaoException("응답 없음")
    }
}
```

---

## 다중 Provider 처리 (ADR-0003 D7)

**MVP: 별도 계정.** 같은 사용자가 Apple 과 Kakao 로 각각 가입하면 별도 user_id 생성. v1.1 에서 "계정 연결" 기능 도입.

→ 가입 분기 로직은 단순:
```kotlin
fun upsertUser(provider: Provider, providerUserId: String, displayNameHint: String): User {
    val existing = oauthIdentityRepository.findByProviderAndProviderUserId(provider, providerUserId)
    if (existing != null) return userRepository.findByIdOrThrow(existing.userId)

    val user = userRepository.save(User.create(displayName = displayNameHint))
    oauthIdentityRepository.save(OAuthIdentity(userId = user.id, provider = provider, providerUserId = providerUserId))
    return user
}
```

---

## Token Refresh

```
POST /auth/refresh { refreshToken }
   │
   ▼
JwtTokenProvider.parse(refreshToken)  → JTI 추출
   │
   ▼
refresh_tokens 조회
   │
   ├─ 없음 / revoked_at != null / expires_at <= NOW()  → 401 InvalidRefreshToken
   │
   └─ 유효 → 새 accessToken 발급 + last_used_at = NOW()
              (refresh token 자체는 그대로 — v1.1 에서 rotation 검토)
```

### 강제 로그아웃 / 로그아웃

| 엔드포인트 | 동작 |
|---|---|
| `POST /auth/logout` | 사용자의 **모든** refresh_tokens 에 `revoked_at = NOW()` |
| `POST /auth/logout/this-device { refreshToken }` | 해당 JTI 만 revoke |

Access token 은 만료(1h) 까지 살아있지만, 보호 endpoint 가 사용자 상태(deleted_at 등) 를 매번 확인하므로 큰 위험 없음. 즉시 무효화가 필요하면 v1.1 에서 blacklist 도입.

---

## Spring Security 설정

```kotlin
@Configuration
class SecurityConfig(
    private val jwtAuthenticationFilter: JwtAuthenticationFilter,
) {
    @Bean
    fun filterChain(http: HttpSecurity): SecurityFilterChain = http
        .csrf { it.disable() }                       // JWT 기반 stateless
        .cors { /* iOS 도메인만 허용 */ }
        .sessionManagement { it.sessionCreationPolicy(SessionCreationPolicy.STATELESS) }
        .authorizeHttpRequests {
            it
                .requestMatchers("/auth/**").permitAll()
                .requestMatchers("/health", "/actuator/health").permitAll()
                .anyRequest().authenticated()
        }
        .addFilterBefore(jwtAuthenticationFilter, UsernamePasswordAuthenticationFilter::class.java)
        .build()
}
```

### 인증 헤더
```
Authorization: Bearer <accessToken>
```
없거나 invalid → 401 (JwtAuthenticationFilter 가 GlobalExceptionHandler 통해 응답).

---

## Controller 에서 사용자 식별

```kotlin
@RestController
@RequestMapping("/users/me")
class UserController(private val userService: UserService) {

    @GetMapping
    fun me(@CurrentUser principal: KickLogPrincipal): UserResponse =
        userService.findById(principal.userId).toResponse()
}
```

- `@CurrentUser` 어노테이션 + `PrincipalArgumentResolver` 가 `SecurityContext` 에서 `KickLogPrincipal` 추출
- `principal.userId` 만 사용. `SecurityContextHolder.getContext()` 직접 호출 금지 (테스트 어려움)

---

## Soft Delete + Cron (ADR-0003 D8)

```kotlin
@Component
class UserPurgeJob(
    private val userRepository: UserRepository,
    private val clock: Clock,
) {
    @Scheduled(cron = "0 0 4 * * *")    // 매일 04:00
    @Transactional
    fun purgeDeletedUsers() {
        val cutoff = clock.instant().minus(30, ChronoUnit.DAYS)
        val targets = userRepository.findByDeletedAtBefore(cutoff)
        targets.forEach { user ->
            userRepository.delete(user)    // CASCADE 로 oauth_identities, refresh_tokens 등 전부 삭제
            log.info("[user-purge] hard deleted user={} deletedAt={}", user.id, user.deletedAt)
        }
    }
}
```

- `Clock` 주입 → 테스트에서 시점 제어
- 위치: `user/service/UserPurgeJob.kt`
- 친구 데이터 경로는 모두 `deleted_at IS NULL` 필터 (조회 쿼리에서 즉시 친구 목록에서 사라짐)

---

## 테스트 패턴

세부는 `docs/spec/test-strategy.md` 참조. 인증 영역 특수 규칙:

| 패턴 | 어떻게 |
|---|---|
| **Apple identityToken** | `AppleIdentityVerifier` 를 Protocol 추상화 후 Stub. `valid-token-{userId}` / `invalid-token` magic 패턴 |
| **Kakao /v2/user/me** | `KakaoOAuthClient` 를 Stub. `valid-kakao-token` → 정상 / `expired-kakao` → 401 |
| **JWT 시간 의존** | `Clock` 주입 — 절대 `Instant.now()` 직접 호출 금지 |
| **Refresh token DB** | Testcontainers 실제 PostgreSQL (Mock 금지) |
| **Soft delete cron** | `UserPurgeJob` 단위 테스트 — `Clock.fixed(...)` 로 시점 고정 |

---

## 보안 체크리스트 (code-reviewer Critical 대상)

- [ ] **모든 보호 endpoint 가 `@CurrentUser` 또는 명시적 SecurityContext 검증을 통과**
- [ ] **다른 사용자 리소스 접근 시 IDOR 방지** — `principal.userId` 와 path variable 비교 또는 friendship 검증
- [ ] **친구 데이터 경로는 `FriendshipAuthorizer.assertCanView(viewerId, targetId)` 통과**
- [ ] **응답에 토큰·apple sub·kakao id·email 노출 없음** (UserResponse 에 절대 포함 X)
- [ ] **에러 응답에 스택트레이스 노출 없음** — `GlobalExceptionHandler` 가 ErrorCode 만 직렬화
- [ ] **JWT 시크릿이 코드/Git 에 없음** — AWS Secrets Manager 또는 환경변수
- [ ] **`/auth/**` 외의 모든 endpoint 가 인증 필수** — `permitAll()` 추가 시 PR 에서 명시 사유

위반은 `references/escalation.md` 의 "보안 경계 변경" 조건으로 사용자 확인 필수.
