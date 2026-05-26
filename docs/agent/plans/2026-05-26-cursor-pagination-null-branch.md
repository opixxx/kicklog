# EXEC_PLAN — cursor-pagination-null-branch

| 항목 | 값 |
|---|---|
| Task | cursor-pagination-null-branch |
| Type | fix |
| Branch | fix/cursor-pagination-null-branch |
| Worktree | /Users/opix/Developer/kicklog/.worktrees/cursor-pagination-null-branch |
| Port | 9000 |
| 생성 시각 | 2026-05-26 20:11 |
| 상태 | `done` |
| 개발 방식 | 작은 fix (변경 30줄 미만) — 기존 테스트로 회귀만 검증 |

---

## 1. 목표 (Goal)

`MatchRepository.findAllByUserIdAfterCursor` 가 첫 페이지(커서 없음)와 다음 페이지(커서 있음) 호출을 단일 쿼리에서 `:cursorPlayedAt IS NULL OR ...` 패턴으로 분기 처리하는데, PostgreSQL JDBC 드라이버가 첫 페이지 호출 시 null 로 들어온 `:cursorPlayedAt`(Instant)·`:cursorId`(Long) 파라미터의 데이터 타입을 prepared statement 단계에서 추론하지 못해 `could not determine data type of parameter` 에러가 발생한다. 첫 페이지/다음 페이지를 쿼리 메서드 수준에서 분리해 해결한다.

## 2. 접근 (Approach)

- `backend/src/main/kotlin/com/opixxx/kicklog/match/repository/MatchRepository.kt`
  - `findFirstPageByUserId(userId, pageable)` 신규 — 커서 없는 첫 페이지 전용 (`WHERE m.userId = :userId` 만, `IS NULL` 분기 제거)
  - `findAllByUserIdAfterCursor(userId, cursorPlayedAt, cursorId, pageable)` — 파라미터를 non-nullable 로 변경, JPQL 의 `IS NULL` 분기 제거
- `backend/src/main/kotlin/com/opixxx/kicklog/match/repository/JpaMatchStore.kt`
  - `findAllByUserId` 에서 `cursor == null` 이면 `findFirstPageByUserId`, 아니면 `findAllByUserIdAfterCursor` 로 분기
- `MatchStore` 인터페이스 시그니처는 그대로 — Service/Controller/InMemoryMatchRepository 변경 없음

## 3. 테스트 케이스 (Test Cases)

기존 `MatchAcceptanceTest` · `MatchServiceTest` · `InMemoryMatchRepository` 기반 테스트가 `findAllByUserId(cursor=null, ...)` 와 `findAllByUserId(cursor=...)` 양쪽 호출 경로를 이미 커버한다. 새 테스트는 추가하지 않고 기존 회귀만 확인.

- 백엔드 회귀: `./gradlew check` 전부 통과 (확인됨)

## 4. 검증 (Verification)

- `cd backend && ./gradlew check` — BUILD SUCCESSFUL (수행 완료)
- 운영 환경에서 매치 목록 첫 페이지 호출 시 PostgreSQL 에러 미발생 확인 (수동, iOS 클라이언트)

## 위험도 / 롤백

- Risk = Safe — JPQL 쿼리 분리, 외부 API/스키마 변경 없음
- 롤백: 본 PR revert

## 학습 기록

- Trigger: production-risk (PostgreSQL 파라미터 타입 추론 한계)
- Root cause: JPQL `:param IS NULL OR m.col < :param` 패턴은 Hibernate→PostgreSQL JDBC 경로에서 nullable 파라미터의 SQL 타입을 결정하지 못해 `could not determine data type of parameter` 발생. Spring Data JPA 로는 안전하다고 흔히 가정하지만 PostgreSQL prepared statement 에서는 깨진다.
- Prevention: 커서/옵션 파라미터는 `IS NULL` 분기 대신 메서드 자체를 분리하거나, JPQL 에서 명시적 `CAST(:param AS timestamp)` 사용을 가이드에 추가 고려.
- Promoted to: 본 EXEC_PLAN 만 기록 (재발 시 `docs/agent/learning.md` 로 승격)
