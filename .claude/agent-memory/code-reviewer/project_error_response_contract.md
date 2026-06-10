---
name: project-error-response-contract
description: KickLog 에러 응답은 HttpStatusEntryPoint(401) 때문에 인증 실패 시 body 가 없어 traceId/code 가 안 실린다
metadata:
  type: project
---

KickLog `SecurityConfig` 는 `.exceptionHandling { authenticationEntryPoint(HttpStatusEntryPoint(HttpStatus.UNAUTHORIZED)) }` 로 401 을 처리한다.
`HttpStatusEntryPoint` 는 status 코드만 쓰고 **응답 body 를 만들지 않는다**.

**Why:** GlobalExceptionHandler 는 `@RestControllerAdvice` 라 DispatcherServlet 안에서 발생한 예외만 잡는다.
Security 필터 단계의 인증 실패(401)·인가 실패(403)는 advice 를 거치지 않으므로 `{code,message,traceId}` body 가 비어 있다.

**How to apply:**
- traceId / ErrorResponse 관련 변경을 리뷰할 때 "401 에도 traceId 가 실린다" 같은 주장이 plan 에 있으면 검증할 것 — 현 구조에선 거짓이다.
- 인증 실패 응답에도 일관된 에러 body 를 원하면 `AuthenticationEntryPoint` 커스텀 구현으로 ErrorResponse 를 직렬화해야 한다 (별도 작업).
- 연계: [[feedback-filter-path-matching]] — JwtAuthenticationFilter 가 raw path literal 비교를 쓰는 것도 같은 보안 필터 계층 이슈.
