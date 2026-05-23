---
name: feedback-search-empty-query
description: 검색 endpoint 의 q 파라미터가 빈/공백 문자열일 때 silent 통과해 전체 dump 가 되는 패턴
metadata:
  type: feedback
---

`@RequestParam("q") query: String` 만 선언하면 누락은 `MissingServletRequestParameterException`
으로 막히지만 `q=""` 또는 `q=%20` 은 그대로 통과한다. JPQL `LIKE '%%'` 는 모든 row 매칭이라
검색 endpoint 가 사실상 "전체 사용자 dump" API 가 된다.

**Why:** KickLog 의 `/users/search` 명세는 "1자 이상 필수" 인데 컨트롤러 검증이 없었고,
InMemory 테스트 fake 도 `trim().contains()` 라 production 과 동일하게 빈 문자열에 모두
매치되어 인수 테스트가 통과하면서 회귀를 가렸다.

**How to apply:**
- 검색/필터 endpoint 리뷰 시 `@RequestParam` 의 `@NotBlank` / `@Size(min=1)` 검증을 우선 확인.
- 인수 테스트에 "빈 문자열 q" / "공백 q" 케이스가 있는지 확인. 없으면 Critical.
- Service 진입부에서 `query.trim().takeIf { it.isNotEmpty() }` 로 normalize + 거부도 OK.
- limit clamp 와 같은 silent 보정은 명세에 명시되어 있으면 OK 지만, 검색어의 silent 통과는
  보안·성능 양쪽으로 위험.

연계: [[feedback-filter-path-matching]] — 같은 류의 silent 통과 패턴.
