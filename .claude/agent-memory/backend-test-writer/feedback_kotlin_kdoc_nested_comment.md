---
name: feedback-kotlin-kdoc-nested-comment
description: Kotlin 주석은 중첩되므로 KDoc 안에 /loadtest/** 같은 Ant 패턴을 그대로 쓰면 컴파일이 깨진다
metadata:
  type: feedback
---

Kotlin 블록 주석은 **중첩된다**. KDoc/블록 주석 안에 `/**` 가 등장하면 새 주석이 열려 닫히지 않고
컴파일이 깨진다. 주석에서 경로 패턴을 설명할 때는 `/loadtest/**` 대신
"`/loadtest` 하위 경로" 처럼 풀어 쓴다.

**Why:** 2026-10-30 concurrency-ceiling-harness 작업에서 실제로 발생해 사용자가 직접 경고했다
(`securityMatcher("/loadtest/**", ...)` 를 KDoc 에 인용하다 컴파일 실패).

**How to apply:** Kotlin 파일(main/test 공통)에 한글 주석·KDoc 을 쓸 때마다. Ant 패턴·glob·
`/* */` 를 포함한 코드 조각을 주석에 인용하려면 백틱 안에서도 `**` 를 피하거나 서술형으로 바꾼다.
