---
name: feedback-filter-path-matching
description: Servlet 필터에서 path 비교 시 raw equals 대신 PathMatcher / shouldNotFilter 를 사용하라는 리뷰 규칙
metadata:
  type: feedback
---

Spring Servlet 필터에서 특정 endpoint 만 우회하려는 가드 (예: DeletedUserGuardFilter) 는
`request.requestURI == "/literal/path"` 직접 비교를 쓰면 안 된다.

**Why:** Spring 6+ 의 path matching 이 trailing slash 동등을 제거했고, raw `requestURI` 는
URL-encoded 형태(`%2F` 등) 및 reverse proxy 의 정규화 차이에 취약하다. 또한 컨트롤러의
`@RequestMapping` 이 바뀌면 필터의 literal 상수와 silent 하게 어긋나 보안 정책이 깨진다.

**How to apply:**
- 필터 코드 리뷰 시 path literal 비교가 있으면 Critical 로 지적.
- 대안 우선순위: (1) `shouldNotFilter` override + `AntPathMatcher`/`PathPatternParser`,
  (2) Service 진입부에서 도메인 상태 체크로 책임 이동 (1인 사이드 규모에 적합),
  (3) `HandlerMapping` 으로 어떤 핸들러로 매핑되는지 확인.
- 함께 확인할 것: cancel-deletion / public endpoint allow-list / actuator 우회 등에서
  같은 패턴이 반복되었는지.

연계: [[feedback-search-empty-query]] — `q` 빈 문자열도 같은 류의 silent 통과 이슈.
