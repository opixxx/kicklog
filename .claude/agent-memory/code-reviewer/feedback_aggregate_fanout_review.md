---
name: feedback-aggregate-fanout-review
description: 메모리 집계 → DB 집계 SQL 전환 리뷰 시 반드시 확인할 항목 — fan-out 분리, UTC 월 경계, COALESCE, 스냅샷 원자성
metadata:
  type: feedback
---

애플리케이션 메모리 집계를 DB 집계 SQL 로 옮기는 리팩토링은 **컴파일·기존 테스트가 다 통과하면서
숫자만 조용히 틀리는** 유형이다. 리뷰 시 아래 순서로 확인한다.

1. **fan-out** — 부모(matches)와 자식(quarter_workouts)을 한 쿼리에서 집계하면 부모 행이
   자식 수만큼 복제되어 `SUM(부모컬럼)` 이 배수가 된다. 집계 단위별 쿼리 분리 여부를 먼저 본다.
   테스트 fixture 가 "경기당 쿼터 1개" 면 fan-out 을 절대 못 잡는다 — fixture 부터 확인.
2. **월/일 경계 타임존** — `EXTRACT(MONTH FROM ts AT TIME ZONE 'UTC')` 의 `AT TIME ZONE` 누락.
   KickLog 는 api-spec §8.1 이 "UTC playedAt.month 기준" 계약. 경계 테스트 데이터는
   `YYYY-12-31T15:00:00Z`(KST 로 다음 해) 처럼 서버 TZ 를 타야 의미가 있다.
3. **COALESCE** — 0건일 때 `SUM`/`MAX` 는 NULL. Kotlin 비-null 매핑이 깨진다. `COUNT` 는 불필요.
4. **나눗셈 위치** — 정수 버림·0 division 계약이 있으면 SQL 이 아니라 Service 에서 나누는 편이
   기존 Kotlin 구현과 반올림이 어긋나지 않는다 (분자·분모를 그대로 내려받는 형태).
5. **스냅샷 원자성** — 1 쿼리를 N 쿼리로 쪼개면 READ COMMITTED 기본 격리에서 각 쿼리가 다른
   스냅샷을 본다. 같은 응답 안에서 `matchCount` 와 `quarterCount` 가 어긋날 수 있다.
   수용하든 `REPEATABLE_READ` 로 올리든 **명시적 판단**을 요구한다.
6. **프로젝션 타입** — [[native-query-projection-types]] 참조.

**Why:** 2026-09-16 `season-stat-sql-aggregation` 리뷰에서 이 체크리스트로 1~4·6 을 검증했고,
5(원자성)와 6(타입)이 테스트가 구조적으로 못 잡는 잔여 리스크로 남았다.

**How to apply:** 집계/통계 관련 PR 에서 SQL 이 추가되면 이 6항목을 기계적으로 대조한다.
H2 인수 테스트만으로는 PostgreSQL 방언 차이를 못 잡으므로 Testcontainers 검증 유무도 함께 본다.
