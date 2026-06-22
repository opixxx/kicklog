---
name: pattern-transaction-template-red-conflict
description: 침묵 분기를 명시 실패로 바꾸는 RED 는 그 침묵 분기에 의존하던 기존 단위 테스트를 동시에 깨뜨린다
metadata:
  type: feedback
---

서비스의 "침묵 fallback 분기"(예: `transactionTemplate?.execute { } ?: action()`)를
"명시적 실패"(null 이면 `IllegalStateException`)로 바꾸는 RED 테스트를 작성할 때,
그 fallback 에 의존해 통과하던 기존 단위 테스트가 GREEN 단계에서 함께 깨진다.

**Why:** 2026-06-10 audit-fixes P3 — `FriendshipService.runInTransaction` 의 무트랜잭션 침묵 분기 제거.
기존 `FriendshipServiceTest` 는 `FriendshipService(repo, repo)` 로 transactionTemplate 없이(null)
`request()` 를 호출해 통과 중이었다. 명시 실패로 바꾸면 이 기존 테스트들도 깨진다.
EXEC_PLAN 도 "생성자 기본값 null 은 단위 테스트 호환 위해 유지하되 트랜잭션 필요 경로에서 명시 실패"
라고만 적어 — 기존 테스트 갱신 필요성이 RED 단계에서 드러나지 않으면 GREEN 에서 회귀로 표면화된다.

**How to apply:**
- RED 보고 시 "기존 테스트 X 가 GREEN 단계에서 함께 수정되어야 한다(transactionTemplate 주입 등)" 를 명시 충돌로 올린다.
- "기존 테스트 수정 금지"(회귀 기준선) 지시와 충돌하므로 새 RED 파일은 따로 만들되, 기존 파일 갱신은 GREEN 구현자/orchestrator 결정에 맡긴다.
- request()/accept()/delete() 등 `runInTransaction` 경유 메서드를 호출하는 기존 단위 테스트를 grep 해 영향 범위를 미리 센다:
  `grep -rn "FriendshipService(" backend/src/test`

관련: [[project-acceptance-test-convention]]
