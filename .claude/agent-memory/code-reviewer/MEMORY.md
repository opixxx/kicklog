# Code Reviewer Memory

반복 리뷰 이슈와 Critical 패턴을 누적한다.

## Usage

- Critical 또는 반복 Major를 발견하면 짧은 패턴으로 추가한다.
- 다음 리뷰에서 같은 패턴을 우선 확인한다.
- 프로젝트 전체 규칙으로 승격할 내용은 `docs/agent/learning.md`의 Update Targets에 따라 원본 문서도 갱신한다.

## Patterns

- [Filter path matching](feedback_filter_path_matching.md) — Servlet 필터에서 `requestURI == "/literal"` 직접 비교 금지, `PathMatcher` / `shouldNotFilter` 사용
- [Search empty query](feedback_search_empty_query.md) — `@RequestParam("q") String` 만 두면 빈 문자열에 전체 dump, `@NotBlank` 필수
- [Profile isolation security](feedback_profile_isolation_security.md) — `@Profile` 격리 엔드포인트는 실제 배포 프로파일명(docker-compose.prod.yml)과 대조해 보안 판정
- [Error response contract](project_error_response_contract.md) — 401/403 은 HttpStatusEntryPoint 라 body 없음 → traceId 안 실림, advice 미경유
- [Instant 응답 포맷 계약](project_instant_response_format.md) — 응답 `Instant` 는 소수부 없는 초 단위(JacksonConfig 전역), `toString()` 미리 변환·비-Instant 시간 타입이 우회로
- [Sentry error tracking](project_sentry_error_tracking.md) — 코어+수동init(starter 미지원), 5xx만 전송, ErrorReporter 경유, PII 비전송, traceId 키 3곳 중복

<!--
### YYYY-MM-DD — <pattern>
- Symptom:
- Check:
- Prevention:
-->
