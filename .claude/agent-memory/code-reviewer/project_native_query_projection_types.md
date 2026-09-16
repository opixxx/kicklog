---
name: native-query-projection-types
description: PostgreSQL 집계 반환 타입(SUM(bigint)=numeric, MAX(int)=integer)이 Spring Data 인터페이스 프로젝션 선언 타입과 어긋나는 문제 — 지금은 암묵 변환으로 통과하나 생성자 프로젝션 전환 시 깨짐
metadata:
  type: project
---

native `@Query` + Spring Data 인터페이스 프로젝션을 리뷰할 때, SQL 집계식의 **실제 반환 타입**을
`pg_typeof` 로 확인하고 프로젝션 getter 타입과 대조한다. PostgreSQL 16 실측:

| 식 | 반환 타입 |
|---|---|
| `SUM(integer)` | `bigint` |
| `SUM(bigint)` (예: `CAST(x AS bigint) * y` 의 합) | **`numeric`** → JDBC `BigDecimal` |
| `MAX(integer)` | **`integer`** (bigint 아님) |
| `COUNT(*)` | `bigint` |
| `EXTRACT(...)` | `numeric` |
| `COALESCE(MAX(double precision), 0)` | `double precision` |

**Why:** `match/repository/SeasonAggregateRows.kt` 가 전 필드를 `Long` 으로 선언하고
"SUM/COUNT 는 bigint 로 돌아온다" 고 주석에 적었지만, `weightedHeartRateSum` 은 numeric,
`longestMatchDistanceM`/`mostSprintCount` 는 integer 로 온다. 인터페이스 프로젝션은
Spring `ConversionService` 가 Number→Number 를 암묵 변환해 주므로 테스트가 전부 통과한다 —
즉 **컴파일·테스트가 못 잡는 종류의 잠복 결함**이다. 나중에 Kotlin data class(생성자 프로젝션)나
`Tuple` 직접 매핑으로 바꾸면 `BigDecimal → Long` 에서 그대로 터진다.

**How to apply:** native 집계 쿼리 리뷰 시
① SQL 에서 `CAST(COALESCE(SUM(...),0) AS bigint)` 로 반환 타입을 못 박았는지, 또는
② Row 타입이 실제 JDBC 타입과 일치하는지 둘 중 하나를 요구한다.
주석에 타입을 적었다면 그 주장이 사실인지도 검증한다. 관련: [[feedback-aggregate-fanout-review]]
