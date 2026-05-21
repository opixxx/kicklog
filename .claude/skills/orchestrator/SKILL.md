---
name: orchestrator
description: >
  KickLog 구현/버그수정/리팩토링 작업의 표준 파이프라인(0~6단계)을 강제하는 오케스트레이터.
  (1) "구현", "추가", "만들어", "엔드포인트", "기능" 등 구현성 요청,
  (2) "버그", "고쳐", "fix" 등 수정 요청,
  (3) "리팩토링", "개선" 요청,
  (4) feature/fix/refactor 브랜치 작업,
  (5) worktree·EXEC_PLAN 필요 작업에 반드시 사용.
  단순 질문·코드 설명·문서 조회는 제외.
---

# KickLog Implementation Orchestrator

모든 구현·버그수정·리팩토링은 0~6단계 파이프라인을 따른다.
단계 건너뛰기 금지, 예외는 명시적 확인 후.

## 트리거 조건

다음 중 하나라도 해당:
- `backend/**/*.kt`, `backend/**/*.kts`, `backend/**/*.sql`, `backend/**/*.yml` 변경 예상
- `ios/**/*.swift`, `ios/**/*.xcconfig`, `ios/**/Info.plist` 변경 예상
- "구현", "만들어", "추가", "수정", "고쳐", "리팩", "버그" 등 키워드
- 새 API endpoint, 새 화면, 새 기능

**사용 안 함**: 단순 코드 설명, 문서 조회, 로그 분석, 상태 확인.

---

## 표준 파이프라인 (0 → 6)

```
0. Intake       → 요구 파싱·관련 문서 스캔·모호점 질문·범위 확정
1. EXEC_PLAN    → 30줄 이상 변경이면 필수, scripts/start-task.sh로 생성
2. Worktree 구현 → linked worktree 내부에서 구현 + 테스트 병행
3. 검증-a (계산적) → compile (백엔드만, iOS는 Xcode 실시간)
4. 검증-b (추론적) → code-reviewer (backend/) / ios-reviewer (ios/) 분기
5. 커밋 + PR     → /pr-guide skill
6. Post-merge   → 트레젝토리 기록
```

복귀 경로:
- Phase 3 실패 → Phase 2 복귀 (자가수정 최대 3회, `references/self-heal-loop.md`)
- Phase 4 Critical → Phase 2 복귀
- 에스컬레이션 조건 충족 → 즉시 정지 (`references/escalation.md`)

---

## 0. Intake

### 0.1 관련 문서 수집 (질문 전 필수)

같은 결정을 두 번 하지 않기 위해 먼저 스캔:
1. **`docs/PRD.md`** — 해당 영역 섹션
2. **`docs/adr/`** — 파일명에 주제 키워드 있으면 읽기
   - 예: 친구 작업 → `0003-data-model-and-api.md` 의 D3, D4
   - 예: HealthKit 작업 → `0004-swiftdata-and-healthkit.md`
   - 예: 호스팅/AWS → `0006-hosting.md`
3. **`docs/agent/plans/`** — 진행 중인 작업 플랜
4. **`docs/agent/trajectories/`** — 최근 비슷한 작업 기록

읽은 내용에 **이미 결정된 규칙·제약·계약**이 있으면 그대로 따른다.
문서가 충돌하면 사용자에게 확정 요청.

### 0.2 미확정 요구 질문

위 문서 조사 후에도 다음이 명확하지 않으면 구현 들어가지 말고 사용자에게 질문:

- 어떤 영역에 속하는가? (`backend/{auth,user,friend,match,venue,place,common}` / `ios/{App,Models,Features/{Games,Season,Friends,Settings},Services}`)
- 새 API인가 기존 변경인가? (Breaking change 여부)
- DB 스키마 변경이 있는가? (있으면 Flyway 마이그레이션 필요)
- iOS 모델 변경이 있는가? (있으면 SwiftData 마이그레이션 필요)
- 친구 권한 검증 필요 영역인가?

추측으로 진행 금지. 모호한 항목은 묶어서 한 번에 질문.

---

## 1. EXEC_PLAN 생성 (30줄 이상 변경 시 필수)

```bash
bash scripts/start-task.sh <task-name> <type>
# type: feature | fix | refactor | chore | docs
```

원자적 생성:
- linked worktree (`../kicklog-<slug>`)
- 브랜치 (`<type>/<slug>`)
- 영구 플랜 파일 (`docs/agent/plans/YYYY-MM-DD-<slug>.md`)
- worktree 루트의 `EXEC_PLAN.md` symlink
- 빈 포트 (9000~9099)
- `.task/` 메타 + `logs/` + 트레젝토리 기록

EXEC_PLAN 필수 섹션 (3섹션 단순화):
1. **목표** (Goal) — 왜 이 변경?
2. **접근** (Approach) — 시그니처 수준 (메서드 시그니처, API endpoint, 핵심 규칙)
3. **테스트 케이스** (Test Cases) — TDD: 어떤 테스트를 먼저 작성할지 명시 (Happy/Unhappy/Edge 분류)
4. **검증** (Verification) — Bash 명령으로 완료 조건

`<TODO:>` 마커가 남아있으면 `enforce-plan.sh` 훅이 코드 편집을 차단한다.

**30줄 미만 작은 변경 면제**: 오타·변수명·작은 리팩토링은 EXEC_PLAN 없이 직접 (TDD도 면제).

---

## 2. Worktree 구현 (TDD: Red → Green → Refactor)

상세 정책: `references/workflow-policy.md`

- 모든 코드 편집은 linked worktree 내부에서
- `main`/`master` 브랜치 메인 디렉토리에서 백엔드/iOS 소스 수정 금지 (`enforce-worktree.sh` 차단)
- 예외 허용: 문서·하네스·CI·iOS README/Assets

### TDD 사이클 (KickLog 표준)

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│ 🔴 RED          │ →  │ 🟢 GREEN        │ →  │ 🔵 REFACTOR     │
│ 실패하는 테스트  │    │ 테스트 통과하는  │    │ 중복 제거 +     │
│ 먼저 작성        │    │ 최소 구현       │    │ 가독성 개선     │
└─────────────────┘    └─────────────────┘    └─────────────────┘
        ↑                                              │
        └──────────── 반복 (다음 테스트 케이스) ──────────┘
```

**원칙**:
- EXEC_PLAN의 "테스트 케이스" 섹션을 순서대로 한 번에 하나씩
- 테스트 작성 후 반드시 **실행해서 실패 확인** (의도한 이유로 실패하는지)
- 최소 구현 = 통과시키는 가장 단순한 코드 (의도적으로 simple)
- Refactor 단계는 테스트 그대로 두고 구현만 개선

### 백엔드 TDD 흐름 (Spring Boot 4 + Kotlin)

**Phase 2 진입 시 자동 위임**: 변경 영역에 따라 `backend-test-writer` agent를 먼저 호출하여 테스트 케이스 생성.

```
1. 🔴 RED — 통합 테스트 작성 (Testcontainers + JUnit5 + AssertJ)
   ├─ Service + Repository 흐름 (예: matchService.upsertMatch)
   ├─ Controller test (@WebMvcTest 또는 통합)
   └─ ./gradlew test → 실패 확인 (RED)

2. 🟢 GREEN — 최소 구현
   ├─ JPA Entity + Repository
   ├─ Service (Application 로직, @Transactional)
   ├─ Controller + DTO (@Valid)
   ├─ Flyway 마이그레이션 (스키마 변경 시)
   └─ ./gradlew test → 통과 확인 (GREEN)

3. 🔵 REFACTOR — 코드 개선
   ├─ 중복 제거 (helper 추출)
   ├─ ErrorCode enum 정리
   ├─ 메서드 20줄 이내 분리
   └─ ./gradlew test → 여전히 통과 확인
```

### iOS TDD 흐름 (Swift Testing + SwiftUI + SwiftData)

**Phase 2 진입 시 자동 위임**: 변경 영역에 따라 `ios-test-writer` agent를 먼저 호출.

```
1. 🔴 RED — Swift Testing 단위 테스트 작성
   ├─ ViewModel @Observable 상태 변화
   ├─ Service (HealthKitService Mock, APIClient Mock 등)
   ├─ Model 메서드 (Match.recalculateHeadlineMetrics 등)
   └─ Cmd+U 또는 xcodebuild test → 실패 확인 (RED)

2. 🟢 GREEN — 최소 구현
   ├─ SwiftData @Model (변경 시)
   ├─ Service (Protocol 정의 + Mock 친화적)
   ├─ ViewModel (@Observable)
   ├─ SwiftUI View
   └─ 테스트 → 통과 (GREEN)

3. 🔵 REFACTOR
   ├─ 중복 추출 (View → ViewModifier, Service helper)
   ├─ Protocol 분리 (Mock 용이성)
   └─ 테스트 → 여전히 통과
```

### UI 테스트 (XCTest UI)는 TDD 안 함
- 빌드 시간 길음 (시뮬레이터 부팅 30초~) — Red→Green 사이클에 부담
- **단위 테스트로 TDD → UI 테스트는 사후 작성** (orchestrator Phase 4 검증-b 단계에서 점검)

코딩 규칙:
- 백엔드: `coding-conventions` skill (자동 로드)
- iOS: `ios-conventions` skill (자동 로드)

### TDD 금지 사항

- ❌ **테스트 없이 구현 코드 작성** — 30줄 이상 변경에 EXEC_PLAN 테스트 케이스 섹션이 비었으면 차단
- ❌ **테스트를 통과시키려 production 코드 외 다른 곳 수정** (테스트 자체 수정 등 우회)
- ❌ **테스트 코드를 비스코프 헬퍼 등으로 의미 없게 만들기** (assertion 없는 테스트)
- ❌ **Refactor 단계에서 새 기능 추가** — Refactor는 동작 유지가 원칙
- ❌ **Mock에만 의존** — 백엔드는 Testcontainers (실제 DB), iOS는 Protocol Mock 균형

---

## 3. 검증-a (계산적 센서)

**빠름, 결정론적**. 하나라도 실패하면 Phase 4 스킵하고 Phase 2 복귀.

### 백엔드
```bash
cd backend
./gradlew compileKotlin       # 컴파일
./gradlew test                # 테스트 (옵션, 큰 변경일 때)
```

### iOS
- **자동 검증 안 함** — Xcode가 실시간 컴파일 에러 표시
- 사용자가 Xcode에서 Cmd+B로 수동 빌드 권장

`Stop` 훅(`verify-and-block.sh`)이 종료 시 백엔드 `compileKotlin` 자동 실행, 실패 시 자가수정 (최대 3회).

---

## 4. 검증-b (추론적 센서)

**Phase 3 통과 후에만 실행**. 변경 파일 경로에 따라 분기:

| 변경 영역 | 호출 서브에이전트 | 실행 조건 |
|---|---|---|
| `backend/**` | `code-reviewer` | 필수 |
| `ios/**` | `ios-reviewer` | 필수 |
| 양쪽 모두 | 둘 다 병렬 호출 | 필수 |
| 테스트 코드 변경/누락 | `backend-test-writer` 또는 `ios-test-writer` | Plan에 테스트 케이스 누락 시 |

**판정**:
- Critical 지적 → Phase 2 복귀
- Major 지적 → 수정 권장 (사용자 결정)
- Minor 지적 → 별도 TODO 또는 후속 PR

---

## 5. 커밋 + PR

`/pr-guide` 스킬에 위임.

요약:
- 백엔드: `./gradlew check` 통과 필수
- iOS: Xcode build 통과 필수 (사용자가 Cmd+B 확인)
- 작은 변경(Safe/Caution): 단일 커밋
- 큰 변경(Risky 이상): feat + chore 2단계 커밋 분리

PR 본문에 `docs/agent/plans/...` EXEC_PLAN 링크 자동 첨부 (worktree 경유 작업인 경우).

---

## 6. Post-merge

- **트레젝토리 기록**: `docs/agent/trajectories/YYYY-MM.log` 에 완료 라인 추가
  - 각 단계 소요 시간 · 재시도 횟수 · 실패 원인 · 최종 커밋 해시
- **worktree 정리**: `git worktree remove <path>`
- v1.1+ `/review-gap-analysis` 스킬로 월 1회 학습

---

## 에스컬레이션 (즉시 정지)

상세: `references/escalation.md`

다음 중 하나라도:
- 자가수정 3회 연속 실패
- EXEC_PLAN과 실제 diff 규모 150% 초과 (scope creep)
- DB 마이그레이션 필요한 변경 (사용자 확인 필수)
- Breaking API 변경
- 보안 경계 변경 (인증·인가·PII)
- HealthKit 권한 set 변경 (Apple 심사 영향)
- 카카오 API 통합 변경

---

## Skill / Agent 맵

| Phase | 담당 | 비고 |
|---|---|---|
| 0 Intake | 이 오케스트레이터 | 질문·범위 확정 |
| 1 EXEC_PLAN | `scripts/start-task.sh` | 오케스트레이터가 실행 |
| 2 Worktree 구현 | 영역별 분기 | `coding-conventions` / `ios-conventions` skill 자동 로드 |
| 3 계산적 검증 | `Stop` 훅 | `verify-and-block.sh` (백엔드 compile) |
| 4 추론적 검증 | `code-reviewer` (backend/) + `ios-reviewer` (ios/) | 영역별 분기 |
| 5 커밋 + PR | `/pr-guide` 스킬 | |
| 5.5 PR 리뷰 (별도) | `/code-review` 스킬 | PR 번호 받아 GitHub 코멘트 등록 |
| 6 Post-merge | 트레젝토리 기록 | `docs/agent/trajectories/` |

---

## 금지 사항

- Intake 단계 건너뛰고 바로 구현
- 30줄 이상 변경에 EXEC_PLAN 생략
- 자가수정 루프에서 `--no-verify`, `-DskipTests`, `@Disabled`로 우회
- 실패 원인 분석 없이 brute-force 재시도
- 에스컬레이션 조건 충족인데 혼자 진행
- `main` 메인 디렉토리에서 백엔드/iOS 소스 직접 수정
- 계획 없이 코드 편집 (훅이 차단)

---

## 참조

- 워크플로 정책: `references/workflow-policy.md`
- 자가수정 루프: `references/self-heal-loop.md`
- 에스컬레이션: `references/escalation.md`
- 코딩 컨벤션 (백엔드): `.claude/skills/coding-conventions/SKILL.md`
- iOS 컨벤션: `.claude/skills/ios-conventions/SKILL.md`
- PR 생성: `.claude/skills/pr-guide/SKILL.md`
- PR 리뷰: `.claude/skills/code-review/SKILL.md`
