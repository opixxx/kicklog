# EXEC_PLAN — instant-seconds-serialization

| 항목 | 값 |
|---|---|
| Task | instant-seconds-serialization |
| Type | fix |
| Branch | fix/instant-seconds-serialization |
| Worktree | /Users/opix/Developer/kicklog/.worktrees/instant-seconds-serialization |
| Port | 9000 |
| 생성 시각 | 2026-08-19 23:10 |
| 상태 | `done` |
| 개발 방식 | **TDD (Red → Green → Refactor)** |

---

## 1. 목표 (Goal)

응답 JSON 의 모든 `Instant` 를 **소수부 없는 초 단위 ISO-8601 UTC** (`2026-08-19T09:38:29Z`) 로 고정한다.

현재 Jackson 3 기본 직렬화는 나노초 값에 따라 `2026-08-19T09:38:29.392099Z` (소수부 있음) 와
`2026-08-19T10:40:00Z` (나노초 0 → 소수부 없음) 를 **비결정적으로** 내보낸다. 이는
`docs/spec/api-spec.md:10` 및 `docs/architecture/api-conventions.md:268` 이 규정한 계약
(`"2026-05-21T10:00:00Z"`) 위반이다.

실제 장애로 이어졌다 — iOS 18.6 (Darwin/24.6.0) 기기의 `JSONDecoder.dateDecodingStrategy = .iso8601`
은 소수부를 거부해, 신규 사용자의 카카오·애플 로그인이 전부 `응답 파싱 실패` 로 실패했다
(2026-08-19 nginx 액세스 로그 확인: signin 200 응답 4회 연속 재시도 후 `/auth/refresh` 없음 = 토큰 저장 실패).
iOS 26 기기는 새 swift-foundation 파서가 소수부를 허용해 증상이 드러나지 않았다.

## 2. 접근 (Approach)

**변경 대상**: `backend/src/main/kotlin/com/opixxx/kicklog/common/config/JacksonConfig.kt` (신규)

```kotlin
// common/config/JacksonConfig.kt
@Configuration
class JacksonConfig {
    @Bean
    fun secondsPrecisionInstantModule(): JacksonModule   // SimpleModule + Instant serializer
}

// 직렬화 규칙
class SecondsPrecisionInstantSerializer : StdSerializer<Instant>(Instant::class.java) {
    override fun serialize(value: Instant, gen: JsonGenerator, ctxt: SerializationContext)
    // DateTimeFormatter.ISO_INSTANT.format(value.truncatedTo(ChronoUnit.SECONDS))
}
```

**양보 불가 규칙**:
- **직렬화(응답)만 변경한다.** 역직렬화(요청)는 관대하게 유지 — 기존 iOS 가 보내는 소수부 포함 값을 계속 받아야 한다.
- **DB 값·도메인 로직은 건드리지 않는다.** 바뀌는 것은 응답에 찍히는 표현뿐이다.
- **커서 페이징에 영향 없음** — `match/service/MatchCursor.kt` 는 Jackson 을 거치지 않고
  `Instant.toString()` 을 직접 Base64 로 인코딩하는 별도 경로다 (확인 완료). 정밀도 손실 없음.
- **밀리초 3자리 고정은 오답** — iOS 18 기본 파서는 소수부 자체를 거부하므로 `.392Z` 도 실패한다.
  반드시 소수부 없는 초 단위여야 한다.

**적용 범위**: 전역 (`UserResponse`, `FriendshipDtos`, `MatchDtos`, `VenueDtos` 등 모든 `Instant` 필드).
`createdAt` 한 곳만 고치면 iOS 18 사용자는 로그인 후 매치·친구 목록에서 동일하게 깨진다.

**Breaking 여부**: 아니다. 명세가 규정한 포맷으로 되돌리는 것이고, 소수부 없는 값은
iOS 18·26 양쪽 파서 모두 파싱 가능하다 (macOS 26 Foundation 으로 실측 확인).

## 3. 테스트 케이스 (Test Cases) — TDD 핵심

> Cucumber Feature 파일이 현재 저장소에 없어(`find src/test -name "*.feature"` → 0건)
> (3-A) 인수 시나리오는 **Gherkin 서술**로 남기고, 실행 가능한 검증은 (3-B) JUnit 으로 작성한다.
> 본 변경은 새 endpoint·DB 마이그레이션·친구 권한 경로가 아니므로 Cucumber 강제 대상이 아니다.

### (3-A) 인수 시나리오 (Gherkin — 서술)

```gherkin
@auth @regression
Feature: 응답 시간 포맷 계약
  Scenario: 로그인 응답의 createdAt 은 소수부가 없다 (Happy)
    Given 나노초가 392099000 인 createdAt 을 가진 사용자
    When 해당 사용자 정보를 응답으로 직렬화하면
    Then createdAt 은 "2026-08-19T09:38:29Z" 형태여야 한다
    And 문자열에 "." 이 포함되지 않아야 한다
```

### (3-B) 유스케이스 / 단위 테스트 케이스

**대상**: `common/config/JacksonConfigTest.kt` — Spring 컨텍스트의 실제 `ObjectMapper` 사용 (`@JsonTest` 또는 `@SpringBootTest`)

#### Happy Path
- [ ] 나노초가 0이 아닌 `Instant` 직렬화 → 소수부 없는 `...Z` 문자열 (`.` 미포함)
- [ ] 나노초가 0인 `Instant` 직렬화 → 동일한 포맷 (기존 동작과 일치, 회귀 없음)
- [ ] `UserResponse` 전체 직렬화 → `createdAt` 이 계약 포맷

#### Unhappy / Edge Cases
- [ ] 소수부가 **포함된** 요청 JSON 역직렬화 → 정상 파싱 (기존 iOS 클라이언트 호환 유지)
- [ ] `Instant.EPOCH` 등 경계값 → `1970-01-01T00:00:00Z`
- [ ] 나노초 999999999 (반올림 아닌 **버림** 확인) → `...:29Z` (`:30Z` 아님)

### 테스트 작성자
- `backend-test-writer` agent 위임 (JUnit 5 + AssertJ)

## 4. 검증 (Verification)

### 자동 검증
```bash
cd backend && ./gradlew compileKotlin
cd backend && ./gradlew check
```

### 시나리오 검증 (배포 후 수동)
```bash
# 1) 배포 후 실제 응답에 소수부가 없는지 — 로그인 성공한 사용자 응답을 nginx 로그 크기로 간접 확인,
#    또는 인증 토큰으로 GET /users/me 직접 호출
curl -s https://api.kicklog.org/v1/users/me -H "Authorization: Bearer <token>" | grep -o '"createdAt":"[^"]*"'
# 기대: "createdAt":"2026-08-19T09:38:29Z"  (소수부 없음)

# 2) iOS 18 기기(Darwin/24.6.0)에서 신규 카카오/애플 로그인 성공 확인
#    nginx 로그에 signin 200 이후 /auth/refresh 가 이어지면 성공
```

### 커버리지
- 신규 코드(serializer + config)는 테스트로 전량 커버

---

## (Optional) 위험도 / 롤백

**Risk = Caution**

- 스키마 변경 없음, 롤백은 커밋 revert + 재배포로 충분
- 응답 표현만 바뀌므로 기존 iOS 26 사용자에게 무영향 (소수부 없는 값도 정상 파싱)
- 정밀도 손실은 **응답 표현 한정** — DB·커서·도메인 로직은 원본 유지

## (Optional) 후속 / 관련 이슈

1. **iOS 근본 수정 (내일 예정)** — `ios/KickLog/Networking/APIClient.swift:31` 의
   `.iso8601` 전략을 소수부 유무 양쪽 모두 받는 커스텀 디코더로 교체.
   `TokenRefresher.swift:67` 도 동일. 서버가 어떤 포맷을 보내도 안전해야 한다.
2. **iOS 18 시뮬레이터 런타임 설치** — 현재 맥에는 iOS 26.4 런타임만 존재.
   최소 지원 버전(iOS 18.0)에서 테스트하지 않은 것이 이번 장애의 구조적 원인.
3. **api-spec.md 에 "소수부 없음" 명시** — 현재 예시로만 암시되어 있어 구현이 어겨도 드러나지 않았다.

## (Optional) 학습 기록

- **Trigger**: production-risk
- **Root cause**: 응답 날짜 포맷이 명세에 예시로만 존재하고 테스트로 고정되지 않아,
  Jackson 기본 동작(나노초 값에 따라 소수부 유무가 갈리는 비결정적 출력)이 계약을 조용히 위반했다.
  최신 iOS 에서만 테스트해 왔기에 관대한 파서에 가려져 드러나지 않았다.
- **Prevention**: 외부 계약(응답 포맷)은 예시가 아니라 **테스트로 고정**한다.
  클라이언트 최소 지원 버전에서 최소 1회 검증한다.
- **Promoted to**: docs/agent/learning.md
