# KickLog API 규약

> ADR-0003 의 endpoint 결정을 **HTTP 레벨 규약** 으로 정형화. 모든 새 endpoint 는 본 규약을 따른다.
> 충돌 시 ADR-0003 의 endpoint 결정이 우선한다.

---

## URL 규칙

### Base
- 운영: `https://api.kicklog.app/v1/...`
- 로컬: `http://localhost:8080/v1/...`

### 버저닝
- 경로 prefix `/v1` 사용 (Header 방식 X)
- Breaking 변경 시 `/v2` 신설, 일정 기간 평행 운영 후 `/v1` deprecation

### 리소스 명명
- 복수형: `/matches`, `/friendships`, `/venues`
- 도메인 = URL prefix
- 동사 사용 금지 (RPC 스타일 X) — 예외: `/auth/{apple,kakao,refresh,logout}` (인증은 자원이 아닌 동작)

### Path Variable
- 내 리소스: `/users/me/...` (절대 `/users/{myId}/...` 금지 — JWT 의 userId 사용)
- 다른 사용자 리소스: `/users/{userId}/...` — 권한 검증 필수
- 멱등 PUT: `/matches/{clientMatchId}` (ADR-0003 D5)

### Query
- 페이지네이션: `?page=0&size=20` (Spring Data Pageable 기본 매핑)
- 필터: `?season=2026&status=accepted`
- 검색: `?q=...&limit=20`

---

## HTTP 메서드 사용 규칙

| 메서드 | 용도 | 멱등 | Body |
|---|---|---|---|
| `GET` | 조회 | ✅ | 없음 |
| `POST` | 신규 생성 (서버가 ID 생성) | ❌ | Request DTO |
| `PUT` | 멱등 업서트 (클라이언트가 ID 결정) | ✅ | Request DTO |
| `PATCH` | 부분 수정 | ❌ (실제론 멱등이지만 표현상) | 부분 필드 DTO |
| `DELETE` | 삭제 | ✅ | 보통 없음 |

### PUT vs POST 결정
- `client_match_id` 같이 **클라이언트가 ID 를 생성**하면 **PUT** (멱등성 확보, ADR-0003 D5)
- `friendships`, `invitations` 처럼 서버가 ID 생성하면 **POST**

---

## 응답 코드

| Status | 용도 |
|---|---|
| `200` | 성공 + Body 있음 |
| `201` | 신규 생성 + Body 에 생성된 리소스 (POST) |
| `204` | 성공 + Body 없음 (DELETE, PATCH no-op) |
| `400` | Bean Validation 실패 / 잘못된 입력 |
| `401` | 인증 실패 (JWT 없음·만료·invalid) |
| `403` | 인가 실패 (친구 아닌데 친구 데이터 접근 등) |
| `404` | 리소스 없음 |
| `409` | 충돌 (중복 가입, friendship 이미 존재 등) |
| `422` | 비즈니스 규칙 위반 (예: 4쿼터 초과) — 선택적, `400` 사용도 OK |
| `500` | 서버 내부 에러 |
| `502/503` | 외부 의존 (Kakao API 실패 등) |

---

## DTO 네이밍

### 패턴 (`coding-conventions` 와 동기)

| 타입 | 패턴 | 예 |
|---|---|---|
| Controller 입력 | `{Action}Request` | `CreateMatchRequest`, `UpdateUserRequest` |
| Service 입력 (Command) | `{Action}Command` | `CreateMatchCommand` |
| Service 출력 (Result) | `{Action}Result` | `CreateMatchResult` |
| Controller 출력 | `{Subject}Response` | `MatchDetailResponse`, `UserResponse` |
| 목록 응답 | `{Subject}ListResponse` 또는 `Page<{Subject}Response>` | — |

### 구조 강제
- 모두 `data class` (Kotlin record)
- Lombok `@Data` 금지 (Kotlin 이라 어차피 안 씀)
- Entity 직접 반환 금지 — 항상 `Response` DTO 로 변환
- Nested DTO 는 별도 파일 또는 같은 파일의 sealed/nested data class

### 예시 — Match PUT
```kotlin
// Controller
@PutMapping("/{clientMatchId}")
fun upsertMatch(
    @CurrentUser principal: KickLogPrincipal,
    @PathVariable clientMatchId: UUID,
    @Valid @RequestBody request: PutMatchRequest,
): ResponseEntity<MatchDetailResponse> {
    val result = matchService.upsert(request.toCommand(principal.userId, clientMatchId))
    return ResponseEntity.ok(result.toResponse())
}

// Request
data class PutMatchRequest(
    @field:NotNull val playedAt: Instant,
    @field:Valid val headline: HeadlineMetrics,
    @field:Size(min = 1, max = 4) val quarters: List<QuarterUpload>,
    val venueId: Long? = null,
    val opponentName: String? = null,
    @field:Pattern(regexp = "[WDL]") val result: String? = null,
    /* ... */
)

fun PutMatchRequest.toCommand(userId: Long, clientMatchId: UUID) = UpsertMatchCommand(
    userId = userId,
    clientMatchId = clientMatchId,
    playedAt = playedAt,
    /* ... */
)
```

---

## 에러 응답 포맷

**모든 에러 응답은 같은 JSON 구조.** `GlobalExceptionHandler` 가 보장.

```json
{
  "code": "MATCH_QUARTER_OVERFLOW",
  "message": "쿼터는 4개를 초과할 수 없습니다",
  "field": "quarters",          // optional, Validation 실패 시
  "traceId": "abc123..."         // optional, 운영 환경에서 X-Request-Id
}
```

### ErrorCode 규약

`common/exception/ErrorCode.kt` 의 enum 으로 관리.

```kotlin
enum class ErrorCode(val status: HttpStatus, val message: String) {
    // 도메인 prefix + reason
    AUTH_INVALID_TOKEN          (HttpStatus.UNAUTHORIZED, "유효하지 않은 토큰입니다"),
    AUTH_EXPIRED_REFRESH        (HttpStatus.UNAUTHORIZED, "리프레시 토큰이 만료되었습니다"),
    AUTH_REFRESH_REUSED         (HttpStatus.UNAUTHORIZED, "이미 사용된 리프레시 토큰입니다"),
    USER_NOT_FOUND              (HttpStatus.NOT_FOUND,    "사용자를 찾을 수 없습니다"),
    USER_DELETED                (HttpStatus.GONE,         "탈퇴한 사용자입니다"),
    FRIEND_UNAUTHORIZED         (HttpStatus.FORBIDDEN,    "친구 관계가 아닙니다"),
    FRIEND_ALREADY_EXISTS       (HttpStatus.CONFLICT,     "이미 친구이거나 요청 대기 중입니다"),
    MATCH_NOT_FOUND             (HttpStatus.NOT_FOUND,    "경기를 찾을 수 없습니다"),
    MATCH_QUARTER_OVERFLOW      (HttpStatus.BAD_REQUEST,  "쿼터는 4개를 초과할 수 없습니다"),
    INVITATION_EXPIRED          (HttpStatus.GONE,         "초대 링크가 만료되었습니다"),
    INVITATION_REVOKED          (HttpStatus.GONE,         "폐기된 초대 링크입니다"),
    EXTERNAL_KAKAO_UNAVAILABLE  (HttpStatus.BAD_GATEWAY,  "카카오 서비스가 일시적으로 응답하지 않습니다"),
    /* ... */
}
```

### 규칙
- ErrorCode 이름: `{DOMAIN}_{REASON}` (대문자 + underscore)
- `message` 는 **한글, 사용자에게 보일 수준**의 문구 (스택트레이스·내부 ID 노출 금지)
- `status` 는 HTTP 상태와 1:1
- 새 ErrorCode 추가 시 **throw 지점 함께 grep 으로 확인** (`code-reviewer` 의 "Dead Code 감지" 규약)

### 예외 클래스 패턴

```kotlin
// common/exception/BaseException.kt
abstract class BaseException(val errorCode: ErrorCode) : RuntimeException(errorCode.message)

// 도메인별
class NotFoundUserException : BaseException(ErrorCode.USER_NOT_FOUND)
class UnauthorizedFriendshipException : BaseException(ErrorCode.FRIEND_UNAUTHORIZED)
class MatchQuarterOverflowException : BaseException(ErrorCode.MATCH_QUARTER_OVERFLOW)
```

- 예외 클래스에 메시지 직접 작성 금지 — 항상 ErrorCode 경유
- `RuntimeException` / `IllegalArgumentException` / `IllegalStateException` 직접 throw 금지 (`code-reviewer` Major)

### GlobalExceptionHandler

```kotlin
@RestControllerAdvice
class GlobalExceptionHandler {

    @ExceptionHandler(BaseException::class)
    fun handleBase(e: BaseException): ResponseEntity<ErrorResponse> =
        ResponseEntity.status(e.errorCode.status).body(ErrorResponse.from(e))

    @ExceptionHandler(MethodArgumentNotValidException::class)
    fun handleValidation(e: MethodArgumentNotValidException): ResponseEntity<ErrorResponse> {
        val first = e.bindingResult.fieldErrors.firstOrNull()
        return ResponseEntity.badRequest().body(ErrorResponse(
            code = "VALIDATION_FAILED",
            message = first?.defaultMessage ?: "입력값이 유효하지 않습니다",
            field = first?.field,
        ))
    }

    @ExceptionHandler(Exception::class)
    fun handleUnknown(e: Exception): ResponseEntity<ErrorResponse> {
        log.error("[unhandled]", e)
        return ResponseEntity.internalServerError().body(ErrorResponse(
            code = "INTERNAL_ERROR",
            message = "서버 내부 오류가 발생했습니다",
        ))
    }
}
```

`RuntimeException` 전체를 catch 하면 NPE / ClassCastException 같은 프로그래밍 버그까지 삼킴 — 구체 타입 또는 `BaseException` 만 잡는다.

---

## 인증·인가 헤더

```
Authorization: Bearer <accessToken>
```

세부는 `auth.md` 참조. 본 문서는 규약만:
- 모든 보호 endpoint 는 이 헤더 필수
- 누락·invalid 시 401 `AUTH_INVALID_TOKEN`
- 만료 시 401 `AUTH_EXPIRED_TOKEN` → iOS 가 `/auth/refresh` 호출 후 재시도

---

## Bean Validation

### 사용 어노테이션
- `@NotNull` / `@NotBlank` / `@Size(min, max)` / `@Pattern` / `@Min` / `@Max`
- `@Valid` 는 `@RequestBody` 와 nested DTO 에 필수
- 메시지는 **한글** (`message = "쿼터는 4개를 초과할 수 없습니다"`)

### 위치
- Request DTO 에만 적용 (Command·Result·Response 에는 X)
- 도메인 검증 (예: 4쿼터 초과)은 **Service 또는 Entity 생성자**에서 다시 — Validation 은 1차 게이트일 뿐, Service 가 최종 책임

---

## 페이지네이션·정렬

### Spring Data Pageable 기반
```
GET /matches?page=0&size=20&sort=playedAt,desc
```

### 응답 포맷
```json
{
  "content": [ /* MatchSummaryResponse 배열 */ ],
  "page": 0,
  "size": 20,
  "totalElements": 137,
  "totalPages": 7,
  "hasNext": true
}
```

→ Spring `Page<T>` 의 기본 JSON 직렬화를 그대로 쓰지 말고, 위 포맷으로 wrapping 하는 `PageResponse<T>` 유틸 사용 (`common/util/PageResponse.kt`).

이유: Spring 기본 `Page` 직렬화는 deprecation 경고 잦고 내부 구조 노출 위험.

---

## 시간·숫자·null 표현

| 타입 | JSON | 비고 |
|---|---|---|
| `Instant` | ISO-8601 UTC `"2026-05-21T10:00:00Z"` | 항상 UTC, 클라이언트가 변환 |
| `LocalDate` | `"2026-05-21"` | 시즌 등 날짜만 |
| `BigDecimal` / `NUMERIC` | 숫자 또는 문자열 — 정밀도 필요하면 문자열 권장 | `geo_lat`, `geo_lng` 등 |
| `null` | `null` 명시 | 키 자체를 빼지 말 것 (iOS 디코딩 일관성) |

---

## 외부 API 호출 응답 처리

### Kakao Local API (운동장 검색 프록시)
- 백엔드가 직접 호출 (REST API 키 클라이언트 노출 방지, ADR-0003 D6.1)
- 응답을 그대로 전달하지 말고 **우리 DTO 로 변환**:
  ```kotlin
  data class PlaceSearchResponse(
      val places: List<Place>,
  ) {
      data class Place(
          val name: String,
          val address: String,
          val lat: BigDecimal,
          val lng: BigDecimal,
          val distanceM: Int?,
      )
  }
  ```
- 카카오 응답 키 (`place_name`, `road_address_name` 등) 가 변경되어도 우리 API 는 안정

### 실패 처리
- 5xx / 타임아웃 → `EXTERNAL_KAKAO_UNAVAILABLE` (502)
- iOS 는 캐시 표시 또는 자동 GPS 만으로 fallback

---

## CORS

iOS 앱은 webview 가 아니라 native HTTP → 사실상 CORS 불필요.
운영 환경에서는 `https://kicklog.app` (Universal Link 도메인) 만 화이트리스트.

---

## API 명세 문서

본 문서는 **규약**. 실제 endpoint 명세는 별도:
- [`docs/spec/api-spec.md`](../spec/api-spec.md) — 9개 도메인 27 endpoint 의 request·response·상태코드·에러·예시 (구현 시 직참조 계약)
- [`docs/spec/diagram.md`](../spec/diagram.md) — ERD + 인증 시퀀스 (Mermaid)
- ADR-0003 의 "API Endpoints" 섹션이 결정 근거(why)

우선순위: **ADR-0003 > 본 문서(규약) > api-spec.md(계약)**. 계약이 어긋나면 갱신 PR 먼저.

v1.1+ 후보: OpenAPI 스펙 자동 생성 (`springdoc-openapi`) → `/v3/api-docs` 로 export.

---

## 체크리스트 (새 endpoint 추가 시)

- [ ] URL 이 `/v1/{domain}/{resource}` 패턴
- [ ] 멱등 자원은 PUT, 신규 생성은 POST, 부분 수정은 PATCH
- [ ] Request DTO 에 `@Valid` + Bean Validation 어노테이션
- [ ] Controller → Command → Service → Result → Response 흐름 준수
- [ ] Entity 직접 반환 0건
- [ ] 보호 endpoint 면 `@CurrentUser` 사용 (또는 `permitAll()` 사유 명시)
- [ ] 친구 데이터 경로면 `FriendshipAuthorizer` 통과
- [ ] 새 ErrorCode 추가 시 throw 지점도 같이
- [ ] ADR-0003 의 endpoint 목록과 일치 (벗어나면 ADR 갱신 PR 먼저)
- [ ] Cucumber 인수 시나리오 1개 이상 (Happy + Unhappy)
