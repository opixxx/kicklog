---
name: project-sentry-error-tracking
description: Sentry 에러 트래킹 연동 설계 — 5xx만 전송, 코어+수동init, DSN 미설정시 비활성
metadata:
  type: project
---

KickLog 백엔드는 Sentry 코어(io.sentry:sentry, NOT starter) + 수동 `Sentry.init` 으로 에러 트래킹을 연동했다 (`common/observability/`).

**Why:** Sentry 8.x Spring Boot starter 가 Spring Boot 4(Framework 7) 미지원 — autoconfiguration 부팅 실패. 무료 티어 quota 절약을 위해 5xx + 미처리 예외만 전송, 4xx 비즈니스 예외는 제외.

**How to apply:**
- 새 에러 캡처 지점은 반드시 `ErrorReporter` 인터페이스 경유 (Sentry static 직접 호출 금지 — 테스트 더블 RecordingErrorReporter 로 검증).
- `GlobalExceptionHandler` 가 단일 캡처 진입점. 다른 곳에서 `Sentry.captureException` 직접 호출하면 중복/PII 누수 위험.
- PII 비전송 정책: `isSendDefaultPii = false`. Sentry 태그/메시지에 이메일·토큰·JWT 넣지 말 것.
- MDC traceId 키는 `"traceId"` 문자열이 3곳(TraceIdFilter / SentryErrorReporter / GlobalExceptionHandler)에 각자 const 로 중복 정의됨 — 공용 상수로 추출 후보.

관련: [[project-error-response-contract]]
