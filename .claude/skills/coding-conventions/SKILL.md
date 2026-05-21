---
name: coding-conventions
description: KickLog 백엔드(Kotlin/Spring Boot 4) 코딩 컨벤션 — 한글 주석/로그/메시지, DTO, 예외 처리, 메서드 길이, 네이밍, 트랜잭션. code-reviewer 에이전트가 사전 로드한다.
user-invocable: false
---

# KickLog 백엔드 코딩 컨벤션

> 본 스킬은 `code-reviewer` agent의 `skills:` 필드로 사전 로드된다.
> 직접 호출 X (`user-invocable: false`).
> iOS 코딩 컨벤션은 별도 (단계 3에서 `ios-conventions` skill 추가 예정).

---

## 1. 언어 규칙

| 대상 | 언어 |
|:----|:----|
| 식별자 (변수·메서드·클래스) | 영문 |
| 주석 / KDoc | 한글 |
| 로그 메시지 | 한글 (플레이스홀더 사용: `log.info("매치 저장 완료: id={}", id)`) |
| 예외 메시지 (ErrorCode) | 한글 |
| Bean Validation 메시지 | 한글 |
| API 응답 message | 한글 |

## 2. 패키지 구조 (Layered)

KickLog는 헥사고날 X — 단순 Spring 레이어드 구조. 1인 사이드 프로젝트에 적합.

```
com.opixxx.kicklog/
├── KicklogApplication.kt
├── config/                  # SecurityConfig, WebConfig, KakaoConfig 등 Bean 설정
├── auth/                    # Sign in with Apple + Kakao + JWT
│   ├── controller/
│   ├── service/
│   └── dto/
├── user/                    # 사용자 프로필·검색·삭제
├── friend/                  # 친구 관계·초대
├── match/                   # 경기 + 쿼터 워크아웃
├── venue/                   # 운동장 마스터
├── place/                   # 카카오 로컬 프록시
├── common/                  # ErrorCode·GlobalExceptionHandler·기본 DTO·유틸
│   ├── exception/
│   └── dto/
└── infra/                   # Kakao client, JWT helper 등 인프라
```

도메인 모듈 (`auth/`, `user/`, ...) 내부는 자유롭게 — Controller·Service·Repository만 두면 충분.

## 3. Strict Rules

### 3.1 의존성 주입
```kotlin
// ✅
@RestController
class MatchController(
    private val matchService: MatchService,
) { ... }

// ❌ @Autowired 필드 주입
class MatchController {
    @Autowired lateinit var matchService: MatchService
}
```

Kotlin은 생성자 주입이 자연 — `@RequiredArgsConstructor` 불필요.

### 3.2 DTO 필수
- **Entity를 Controller에서 직접 반환 금지** — Response DTO 사용
- Request/Response는 `data class` 또는 record (Kotlin)
- DTO 흐름: `Request → Command → Service → Result → Response` (작은 경우 단순화 가능)

```kotlin
// ✅
data class CreateVenueRequest(
    @field:NotBlank(message = "운동장 이름을 입력해주세요")
    @field:Size(max = 100)
    val name: String,
    @field:DecimalMin("-90.0")
    @field:DecimalMax("90.0")
    val geoLat: Double,
    @field:DecimalMin("-180.0")
    @field:DecimalMax("180.0")
    val geoLng: Double,
)

data class VenueResponse(
    val id: Long,
    val name: String,
    val geoLat: Double,
    val geoLng: Double,
)
```

### 3.3 입력 검증
- Request DTO에 Bean Validation 적용
- Controller 메서드에 `@Valid` 필수
- 메시지는 한글

### 3.4 메서드 길이
- 메서드는 한 가지 일만, **최대 20줄**
- 길어지면 private helper로 분리

### 3.5 트랜잭션
```kotlin
@Service
class MatchService(...) {
    @Transactional
    fun upsertMatch(userId: Long, clientMatchId: UUID, command: UpsertMatchCommand): MatchResult { ... }

    @Transactional(readOnly = true)
    fun findById(userId: Long, matchId: Long): MatchResult { ... }
}
```

- 외부 API 호출 (카카오 등)은 트랜잭션 **밖**에서
- 읽기 전용은 `readOnly = true`

## 4. 네이밍 컨벤션

| 타입 | 패턴 | 예시 |
|:----|:----|:----|
| Controller | `{Entity}Controller` | `MatchController` |
| Service | `{Entity}Service` | `MatchService` |
| Repository | `{Entity}Repository` | `MatchRepository` (Spring Data JPA 인터페이스) |
| Entity | `{Entity}` (도메인 이름 그대로) | `Match`, `User`, `Friendship` |
| Request DTO | `{Action}{Entity}Request` | `CreateVenueRequest`, `UpsertMatchRequest` |
| Response DTO | `{Entity}{Variant}Response` | `MatchDetailResponse`, `MatchSummaryResponse` |
| Command | `{Action}{Entity}Command` | `CreateVenueCommand` |
| Result | `{Action}{Entity}Result` | `CreateVenueResult` |
| Domain Exception | `{Reason}{Entity}Exception` | `NotFoundMatchException`, `UnauthorizedFriendshipException` |
| ErrorCode | `{DOMAIN}_{REASON}` | `MATCH_NOT_FOUND`, `FRIENDSHIP_UNAUTHORIZED` |
| Config | `{Domain}Config` | `SecurityConfig`, `KakaoConfig` |

## 5. 예외 처리

### 5.1 ErrorCode enum 경유
```kotlin
// common/exception/ErrorCode.kt
enum class ErrorCode(val status: HttpStatus, val message: String) {
    // Match
    MATCH_NOT_FOUND(HttpStatus.NOT_FOUND, "경기를 찾을 수 없습니다"),
    MATCH_INVALID_QUARTER(HttpStatus.BAD_REQUEST, "쿼터 정보가 올바르지 않습니다"),
    // User
    USER_NOT_FOUND(HttpStatus.NOT_FOUND, "사용자를 찾을 수 없습니다"),
    USER_ALREADY_DELETED(HttpStatus.GONE, "이미 삭제된 사용자입니다"),
    // Friendship
    FRIENDSHIP_UNAUTHORIZED(HttpStatus.FORBIDDEN, "친구가 아닙니다"),
    // 등
}

// common/exception/KicklogException.kt
abstract class KicklogException(val errorCode: ErrorCode) : RuntimeException(errorCode.message)

class NotFoundMatchException : KicklogException(ErrorCode.MATCH_NOT_FOUND)
```

### 5.2 GlobalExceptionHandler
- `@RestControllerAdvice`에서 `KicklogException`을 잡아 일관된 응답 형식 반환
- Bean Validation 에러는 `MethodArgumentNotValidException`을 잡아 한글 메시지로 변환

### 5.3 금지
- `try { ... } catch (e: Exception) { /* ignore */ }` 에러 삼키기 금지
- `IllegalArgumentException` 직접 던지기 금지 — 도메인 예외 사용
- `null!!` (force unwrap) 비즈니스 로직에서 금지

## 6. 로그

```kotlin
private val log = LoggerFactory.getLogger(this::class.java)

// ✅
log.info("경기 저장 완료: userId={}, matchId={}", userId, matchId)
log.warn("초대 토큰 만료: token={}, expiresAt={}", token, expiresAt)
log.error("카카오 API 호출 실패: status={}, body={}", status, body, ex)

// ❌
log.info("경기 저장 완료: userId=$userId, matchId=$matchId")  // 문자열 결합 (성능 저하)
log.error("카카오 API 실패", ex.message)  // exception 객체 없이 message만
```

- 플레이스홀더 `{}` 사용 (지연 평가)
- Exception은 마지막 인자로 전달 (스택 트레이스 자동 출력)
- 민감 정보 로그 금지 (이메일·토큰·비밀번호)

## 7. SOLID 요약

| 원칙 | 위반 예시 |
|:----|:----|
| **SRP** (단일 책임) | `validateAndCreateAndNotify()` |
| **OCP** (확장 O 수정 X) | if-else 분기 대신 다형성 |
| **LSP** (하위 타입 대체) | 하위 타입이 상위 계약 깨뜨림 |
| **ISP** (인터페이스 분리) | 불필요한 메서드 의존 |
| **DIP** (추상화 의존) | 직접 구현체 의존 (`@Autowired KakaoLocalClientImpl`) |

## 8. Anti-pattern (KickLog 컨텍스트)

| Anti-pattern | 대안 |
|:----|:----|
| Service 안에서 직접 HTTP 호출 | 별도 `*Client` 컴포넌트로 분리 (테스트 용이) |
| Entity를 Response로 직접 반환 | `Response.from(entity)` 매퍼 |
| 모든 쿼리에 `findAll()` | 필요한 필드만 SELECT (DTO Projection 또는 `@Query`) |
| `@OneToMany` 무분별 사용 | Aggregate root에만 + fetch 전략 명시 (`@OneToMany(fetch = LAZY)`) |
| 트랜잭션 안에서 카카오 API 호출 | 외부 API는 트랜잭션 밖 |
| `@Transactional` 만으로 멱등성 가정 | `client_match_id` UNIQUE 제약 등 DB 레벨 보장 |
| 매직 넘버 | 의미 있는 상수 (`SPRINT_THRESHOLD_KMH = 14.0`) |
| `@Disabled` 테스트 누적 | 즉시 수정 또는 삭제 |

## 9. 친구 데이터 접근 권한

친구의 데이터를 조회할 때는 **반드시** 친구 관계 확인:

```kotlin
@Service
class FriendMatchService(...) {
    @Transactional(readOnly = true)
    fun findFriendMatches(viewerId: Long, friendUserId: Long): List<MatchSummaryResponse> {
        // 1. 친구 관계 확인 (정렬 pair + status=accepted + deleted_at IS NULL)
        if (!friendshipService.isAccepted(viewerId, friendUserId)) {
            throw UnauthorizedFriendshipException()
        }
        // 2. 심박수 hide 토글 확인
        val friend = userService.findById(friendUserId)
            ?: throw NotFoundUserException()
        
        // 3. 데이터 조회
        val matches = matchRepository.findByUserIdOrderByPlayedAtDesc(friendUserId)
        
        // 4. 권한 기반 마스킹 (심박수)
        return matches.map { MatchSummaryResponse.from(it, hideHeartRate = friend.hideHeartRate) }
    }
}
```

## 10. 참조

- 핵심 결정: `docs/adr/0001-mvp-scope.md`
- 데이터 모델: `docs/adr/0003-data-model-and-api.md`
- 제품 요구: `docs/PRD.md`

---

> **iOS 코딩 컨벤션**은 단계 3에서 `.claude/skills/ios-conventions/SKILL.md`로 별도 작성.
> 본 스킬은 백엔드(Kotlin/Spring) 전용.
