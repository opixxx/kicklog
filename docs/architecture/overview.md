# KickLog 백엔드 아키텍처 — Overview

> ADR 들이 **why** 를 결정한다면, 본 문서는 그 결정의 **how (코드/패키지 레벨 적용)** 를 정한다.
> 충돌 시 ADR 이 우선한다.

---

## 한 줄 요약

**구조는 3-tier (Controller → Service → Repository) + 도메인별 패키지, 모델링은 DDD-lite (Rich Aggregate + VO + Ubiquitous Language).**
iOS 가 1차 SoT, 백엔드는 백업 + 친구 공유 채널.

헥사고날 Port/Adapter 는 도입하지 않는다 (ADR-0003 Consequences). 단, 모델링 측면의 DDD 는 적용 — 세부는 [`domain-modeling.md`](./domain-modeling.md).

---

## 기술 스택

| 레이어 | 기술 |
|---|---|
| 언어 | Kotlin (JDK 17 — Amazon Corretto, ADR-0006 D3) |
| 프레임워크 | Spring Boot 4 |
| DB | PostgreSQL 16 (RDS, ADR-0006) |
| 마이그레이션 | Flyway (`db/migration/V*__*.sql`) |
| 보안 | Spring Security + JWT (ADR-0003 D7.1) |
| 외부 통합 | Apple Sign-In JWKS, Kakao OAuth, Kakao Local API |
| 배포 | Docker multi-stage → EC2 + docker-compose (ADR-0006 D4) |

---

## 패키지 구조

루트: `com.opixxx.kicklog`

```
com.opixxx.kicklog/
├── KicklogApplication.kt                # @SpringBootApplication
├── common/                              # 횡단 관심사 (인증·예외·설정·유틸)
│   ├── config/                          # SecurityConfig, WebClientConfig, AsyncConfig 등
│   ├── exception/                       # BaseException, ErrorCode, GlobalExceptionHandler
│   ├── security/                        # JWT 발급/검증, Filter, Principal
│   └── util/                            # Clock provider, Base62 인코더 등
├── auth/                                # Sign in with Apple + Kakao + JWT 갱신
│   ├── controller/                      # AuthController
│   ├── service/                         # AuthService, AppleIdentityVerifier, KakaoOAuthClient
│   ├── repository/                      # OAuthIdentityRepository, RefreshTokenRepository
│   ├── entity/                          # OAuthIdentity, RefreshToken
│   └── dto/                             # Apple/Kakao SignIn Request/Response, Refresh DTO
├── user/                                # display_name, hide_heart_rate, soft delete
│   ├── controller/                      # UserController
│   ├── service/                         # UserService, UserPurgeJob (@Scheduled)
│   ├── repository/                      # UserRepository
│   ├── entity/                          # User
│   └── dto/                             # UserResponse, UpdateUserRequest, SearchUserResponse
├── friend/                              # friendship + invitations
│   ├── controller/                      # FriendshipController, InvitationController
│   ├── service/                         # FriendshipService, InvitationService
│   ├── repository/                      # FriendshipRepository, FriendInvitationRepository
│   ├── entity/                          # Friendship, FriendInvitation
│   └── dto/                             # *Request, *Response
├── match/                               # matches + quarter_workouts
│   ├── controller/                      # MatchController
│   ├── service/                         # MatchService
│   ├── repository/                      # MatchRepository, QuarterWorkoutRepository
│   ├── entity/                          # Match, QuarterWorkout
│   └── dto/                             # PutMatchRequest, MatchDetailResponse 등
├── place/                               # 카카오 Local API 프록시 (ADR-0003 D6.1)
│   ├── controller/                      # PlaceController
│   ├── service/                         # PlaceService, KakaoLocalClient
│   └── dto/                             # PlaceSearchResponse
├── venue/                               # 개인 운동장
│   ├── controller/                      # VenueController
│   ├── service/                         # VenueService
│   ├── repository/                      # VenueRepository
│   ├── entity/                          # Venue
│   └── dto/                             # VenueRequest/Response
└── stat/                                # 시즌 통계 (집계 read-only)
    ├── controller/                      # StatController
    ├── service/                         # StatService
    └── dto/                             # SeasonStatResponse
```

### 도메인 추가 규칙
- 새 도메인 = `com.opixxx.kicklog.<domain>/{controller,service,repository,entity,dto}` 의 5개 서브패키지
- 한 도메인에 entity 1~3개. 그 이상이면 분할 검토.
- 도메인 간 직접 의존 금지 — 다른 도메인 데이터 필요 시 그 도메인의 Service 를 주입 (Repository 직접 X)

---

## 레이어 흐름

```
HTTP Request
    │
    ▼
┌──────────────────┐
│  Controller      │  @RestController
│                  │  Request DTO 받음, @Valid 검증
│                  │  → Command 로 변환 후 Service 호출
│                  │  ← Result 받아서 Response DTO 로 변환
└──────────────────┘
    │
    ▼
┌──────────────────┐
│  Service         │  @Service @Transactional
│                  │  비즈니스 로직, 트랜잭션 경계
│                  │  외부 의존(Client·Repository) 조율
│                  │  도메인 예외 throw
└──────────────────┘
    │
    ▼
┌──────────────────┐
│  Repository      │  JpaRepository 상속
│                  │  단순 CRUD + 커스텀 쿼리(@Query 또는 querydsl 후보)
└──────────────────┘
    │
    ▼
PostgreSQL
```

### 트랜잭션 경계
- `@Transactional` 은 **Service 메서드**에만. Controller·Repository 에는 X.
- 읽기 전용은 `@Transactional(readOnly = true)`.
- 외부 API 호출(Kakao, Apple JWKS)은 트랜잭션 밖에서 처리 (롤백 시 외부 효과 무효화 불가능).

---

## DTO 흐름 — Request → Command → Result → Response

도메인 간 결합도를 낮추고 Service 시그니처를 안정화하기 위해 4종 분리.

```kotlin
// Controller 입력
data class CreateMatchRequest(
    @field:NotNull val clientMatchId: UUID,
    @field:NotNull val playedAt: Instant,
    /* ... */
)

// Service 입력 (Controller 가 변환)
data class CreateMatchCommand(
    val userId: Long,
    val clientMatchId: UUID,
    val playedAt: Instant,
    /* ... */
)

// Service 출력 (Entity 가 아님!)
data class CreateMatchResult(
    val matchId: Long,
    val createdAt: Instant,
    /* ... */
)

// Controller 출력 (Result 가 변환)
data class MatchDetailResponse(
    val id: Long,
    val playedAt: Instant,
    val quarters: List<QuarterResponse>,
    /* ... */
)
```

### 변환 책임
- `Request → Command`: Controller 가 직접 (확장 함수 `Request.toCommand(userId)` 권장)
- `Service 내부에서 Entity ↔ Result`: Service 내부 private 함수 또는 `<Entity>Mapper` 객체
- `Result → Response`: Controller 가 직접

### 금지
- ❌ Controller 에서 Entity 직접 반환
- ❌ Service 에서 Request/Response DTO 직접 다룸
- ❌ Entity 를 `@RequestBody` 로 받음

세부 네이밍·구조는 `api-conventions.md` 참조.

---

## 외부 통합 위치

| 외부 시스템 | Client 위치 | 용도 |
|---|---|---|
| **Apple JWKS** | `auth/service/AppleIdentityVerifier.kt` | identity token JWT 검증 |
| **Kakao OAuth** (`/v2/user/me`) | `auth/service/KakaoOAuthClient.kt` | accessToken 으로 사용자 정보 조회 |
| **Kakao Local API** (keyword search) | `place/service/KakaoLocalClient.kt` | 운동장 검색 프록시 (ADR-0003 D6.1) |
| **AWS Secrets Manager** | `common/config/SecretsConfig.kt` (예정) | 운영 환경 시크릿 로드 (ADR-0006 D6) |

### 외부 API 호출 규칙
- `WebClient` 사용 (RestTemplate 금지)
- 타임아웃 명시: connect 3s, read 5s
- 예외는 `External{Service}Exception` 으로 wrapping 후 throw
- 테스트는 `WireMock` 또는 Protocol 추상화 후 Mock (`docs/spec/test-strategy.md`)

---

## DB / Flyway

| 위치 | 설명 |
|---|---|
| `backend/src/main/resources/db/migration/V*__*.sql` | Flyway 마이그레이션 |
| `backend/src/main/resources/db/migration/V1__init.sql` | ⚠️ placeholder — ADR-0003 채택 후 V2 부터 실 스키마 |
| `backend/src/main/resources/db/migration/V2__core_schema.sql` (예정) | ADR-0003 의 9개 테이블 (users, oauth_identities, refresh_tokens, friendships, friend_invitations, venues, matches, quarter_workouts) |

스키마 변경 규칙:
- 새 마이그레이션은 **항상 V{N+1}__** 신규 파일. 기존 V 수정 금지 (적용 후엔 immutable).
- Breaking 변경 (컬럼 삭제·이름 변경)은 `references/escalation.md` 의 "DB 마이그레이션" 조건 — 사용자 확인 필수.

---

## 인증·인가 진입점

- **JWT 발급/검증**: `common/security/` — 모든 보호 endpoint 가 통과하는 단일 진입점
- **인가 검사** (특히 friendship 권한): `friend/service/FriendshipAuthorizer.kt` (예정) — 친구 데이터 접근 전 `friendship` 존재 + `accepted` 검증
- **친구 데이터 경로** 추가 시 반드시 `FriendshipAuthorizer` 통과 — 위반은 code-reviewer Critical

세부 흐름은 `auth.md` 참조.

---

## 핵심 규약

| 규약 | 위치 / 참조 |
|---|---|
| **도메인 모델링 정책 (3-tier + DDD-lite)** | [`domain-modeling.md`](./domain-modeling.md) |
| API 규약 (URL prefix·인증 헤더·에러 응답) | [`api-conventions.md`](./api-conventions.md) |
| API 명세 (endpoint별 req/res·에러·예시) | [`../spec/api-spec.md`](../spec/api-spec.md) |
| 다이어그램 (ERD·인증 시퀀스) | [`../spec/diagram.md`](../spec/diagram.md) |
| 인증 흐름 | [`auth.md`](./auth.md) |
| 코딩 컨벤션 (네이밍·DTO·예외·트랜잭션) | `.claude/skills/coding-conventions/SKILL.md` |
| 테스트 전략 | `docs/spec/test-strategy.md` |
| 도메인 모델·API endpoint 결정 | `docs/adr/0003-data-model-and-api.md` |
| 호스팅·운영 | `docs/adr/0006-hosting.md` |
| MVP 스코프 | `docs/adr/0001-mvp-scope.md` |

---

## 진화 경계 (v1.1+)

다음은 **MVP 에서 의도적으로 단순화한 것** — 변경 시 ADR 갱신 필요:

- 헥사고날 Port/Adapter 도입 (현재 단순 3-tier, 단 DDD-lite 는 적용 — `domain-modeling.md`)
- Domain Event / CQRS (`domain-modeling.md` 의 도입 단계 5~6)
- 1분 시계열 / GPS 경로 / 히트맵 저장 (ADR-0003 D1 v1.1+ 후보)
- PostGIS 도입 (ADR-0003 D6 v1.1+)
- Refresh token rotation, 디바이스별 세션 관리 (ADR-0003 D7.1 v1.1+)
- 큐 + exponential backoff 동기화 (ADR-0003 D9 v1.1+)
- 공유 운동장 (ADR-0003 D6 v1.1+)
- 멀티 디바이스 지원 / iCloud Sync (ADR-0004 후속)
