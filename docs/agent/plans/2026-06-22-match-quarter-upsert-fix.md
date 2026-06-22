# EXEC_PLAN — match-quarter-upsert-fix

| 항목 | 값 |
|---|---|
| Task | match-quarter-upsert-fix |
| Type | fix |
| Branch | fix/match-quarter-upsert-fix |
| Worktree | /Users/opix/Developer/kicklog/.worktrees/match-quarter-upsert-fix |
| Port | 9000 |
| 생성 시각 | 2026-06-22 16:57 |
| 상태 | `in-progress` |
| 개발 방식 | **TDD (Red → Green → Refactor)** |

---

## 1. 목표 (Goal)

이미 저장된 경기를 다시 PUT(`PUT /matches/{clientMatchId}`)할 때 — iOS의 **지표 재계산·재라벨링** 시나리오 — 백엔드가 `quarter_workouts (match_id, quarter_number)` unique 제약 위반으로 **500**을 던져 저장이 반영되지 않는 버그를 고친다.

**근본 원인**: `Match.replaceQuarters`가 기존 쿼터를 `clear()`(DELETE 예약) 후 새로 `add()`(INSERT 예약)하는데, `QuarterWorkout`이 `@GeneratedValue(IDENTITY)`라 Hibernate가 **새 INSERT를 기존 행 DELETE보다 먼저** 실행 → 같은 `(match_id, quarter_number)` 충돌. 최초 저장(INSERT)만 성공하고 이후 모든 수정 PUT이 실패하던 구조.

## 2. 접근 (Approach)

**변경 대상**: `backend/src/main/kotlin/com/opixxx/kicklog/match/entity/`

1. **`Match.replaceQuarters` — clear+add → in-place 업데이트** (Match.kt)
   - `quarter_number`를 키로 매칭: 들어온 쿼터 중 기존에 있으면 **UPDATE**, 없으면 **INSERT**, 이번에 안 들어온 기존 쿼터만 **DELETE**(orphanRemoval).
   - 같은 `(match_id, quarter_number)` 행은 갈아엎지 않고 갱신 → unique 충돌 원천 제거.

2. **`QuarterWorkout.applyMetrics(command)` 추가** (QuarterWorkout.kt)
   - 기존 엔티티의 지표·시각 필드를 command 값으로 in-place 갱신하는 메서드.

3. **`Match`에 unique 제약 명시** (Match.kt)
   - `@Table(uniqueConstraints = [UniqueConstraint(columnNames = ["match_id", "quarter_number"])])`
   - **이유**: 현재 unique 제약이 Flyway V5 SQL에만 있고 엔티티엔 없어, test 프로파일(H2 `ddl-auto: create-drop`, `flyway.enabled: false`)에선 제약이 생성되지 않아 이 버그가 테스트로 잡히지 않았다. 엔티티에 명시하면 ① 운영 스키마와 정합 ② 테스트 DB에도 제약 생성되어 회귀 테스트가 RED를 낸다.

**양보 불가 규칙**:
- DB 스키마(운영) 변경 없음 — V5의 제약은 이미 존재. 엔티티 메타데이터만 명시.
- 멱등성: 같은 경기를 N번 PUT해도 항상 200 + 최신 지표 반영.
- 트랜잭션 경계: 기존 `@Transactional fun saveMatch` 유지.
- iOS 클라이언트 변경 불필요 (계약 동일).

## 3. 테스트 케이스 (Test Cases) — TDD 핵심

> **🔴 RED 먼저, 🟢 GREEN 다음, 🔵 REFACTOR 마지막**
> 통합 테스트 위치: `MatchAcceptanceTest` (@SpringBootTest + MockMvc). RED가 성립하려면 엔티티 unique 제약 명시가 선행돼야 함.

### Happy Path
- [ ] **기존 경기 재PUT 시 200 + 지표 갱신** — 같은 clientMatchId로 2회 PUT(2번째는 distanceM 등 다른 값) → 2번째 응답 200(OK) + 갱신된 지표 반영 + 쿼터 수 동일. **(이 버그의 핵심 회귀 테스트)**
- [ ] **최초 PUT은 201(Created)** — 신규 경기 첫 PUT → 201 (기존 동작 회귀 없음 확인)

### Unhappy Path / Edge Cases
- [ ] **쿼터 구성 변경 재PUT** — 2쿼터 경기를 1쿼터로 줄여 재PUT → 200 + 빠진 쿼터 DELETE 반영(쿼터 1건만 남음). orphanRemoval 경로 검증.
- [ ] **(기존 테스트 회귀)** 기존 MatchAcceptanceTest / MatchServiceTest 전부 통과 유지.

### 테스트 작성자 (자동 위임)
- `backend-test-writer` agent — `MatchAcceptanceTest`에 재PUT 시나리오 추가 (실제 DB 제약 검증 위해 통합 테스트로).

## 4. 검증 (Verification)

### 자동 검증
```bash
cd backend && ./gradlew test --tests "*MatchAcceptanceTest" --tests "*MatchServiceTest"
cd backend && ./gradlew check
```

### 시나리오 검증 (수동, 사용자)
- iOS 배포 앱(prod, 백엔드 배포 후)에서 0지표 경기 → "지표 재계산" → 화면 나갔다 다시 진입 → **지표 유지**(0으로 안 돌아감).

## (Optional) 위험도 / 롤백

- **Risk: Caution** — 도메인 로직 변경이나 DB 스키마(운영) 변경 없음, 계약 동일. 회귀 테스트로 보호.
- 롤백: 단일 커밋 revert.

## (Optional) 학습 기록

- Trigger: missing-test (production-risk)
- Root cause: ① IDENTITY + orphanRemoval clear/add 패턴의 INSERT-before-DELETE 순서 충돌 ② 엔티티에 unique 제약 미명시 + test 프로파일이 H2 create-drop이라 제약이 테스트 스키마에 없어 회귀 미탐지.
- Prevention: unique 제약은 엔티티에도 명시(스키마-엔티티 정합) → 후보를 learning.md 승격 검토.
- Promoted to: (Phase 6에서 판단)

---

> 완료 시: `상태` 필드를 `done`으로 변경하고 PR 본문에 본 파일 링크 첨부.
