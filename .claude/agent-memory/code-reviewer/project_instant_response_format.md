---
name: instant-response-format
description: 응답 Instant 는 소수부 없는 초 단위 ISO-8601 고정(JacksonConfig 전역 모듈) — iOS 18 .iso8601 파서가 소수부를 거부해 실제 로그인 장애가 났다
metadata:
  type: project
---

응답 JSON 의 모든 `Instant` 는 **소수부 없는 초 단위 ISO-8601 UTC** 여야 한다.
`common/config/JacksonConfig.kt` 의 `JacksonModule` 빈(`SecondsPrecisionInstantSerializer`)이 전역 강제한다.
역직렬화(요청)는 관대하게 유지 — 기존 클라이언트가 소수부 포함 값을 보낸다.

**Why:** 2026-08-19 운영 장애. Jackson 3 기본 직렬화는 나노초가 0 이면 소수부를 생략하고 0 이 아니면
붙이는 **비결정적 출력**이라, 같은 엔드포인트가 값에 따라 다른 포맷을 냈다. iOS 18.6(Darwin/24.6.0)의
`JSONDecoder.dateDecodingStrategy = .iso8601` 이 소수부를 거부해 신규 사용자의 카카오·애플 로그인이 전부
"응답 파싱 실패"로 깨졌다. iOS 26 은 새 파서라 증상이 가려져 있었다. 계약(`docs/spec/api-spec.md` §시간,
`docs/architecture/api-conventions.md`)은 원래부터 초 단위를 규정했는데 **테스트로 고정하지 않아** 조용히 어겨졌다.

**How to apply (리뷰 시 확인 순서):**
1. 새 Response DTO 에 `LocalDateTime` / `ZonedDateTime` / `OffsetDateTime` / `LocalTime` 필드가 들어오면 지적 —
   전역 모듈은 `Instant` 만 커버한다. 현재 응답 DTO 는 `Instant` + `LocalDate`(미사용) 뿐이다.
2. `Instant.now().toString()` 처럼 **문자열로 미리 변환해 내보내는 코드**는 모듈을 우회한다
   (예: `HealthCheckController` 의 `timestamp`). 타입 그대로 넘겨야 한다.
3. Jackson 을 안 거치는 경로(`match/service/MatchCursor.kt` 의 Base64 커서, JWT 클레임)는 원본 정밀도 유지 —
   의도된 동작이니 "일관성" 이유로 바꾸라고 하지 말 것.
4. `JwtTokenProvider` / `AppleIdentityVerifier` 는 **Jackson 2(`com.fasterxml`) ObjectMapper 를 직접 생성**해
   쓰므로 전역 모듈 영향 밖이다. 여기에 시간 필드가 추가되면 별도 대응 필요.
5. Boot 4 + Jackson 3 에서 `tools.jackson.databind.JacksonModule` 빈은 `JacksonAutoConfiguration` 의
   `StandardJsonMapperBuilderCustomizer` 가 자동 등록한다(검증 완료). 같은 `JsonMapper` 빈이
   `JacksonJsonHttpMessageConverter`(서버·클라이언트 양쪽)에 주입되므로 ObjectMapper 레벨 테스트가
   응답 경로를 대표한다.

관련: [[error-response-contract]]
