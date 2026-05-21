# AGENTS.md

이 파일은 Codex가 KickLog 저장소에서 작업할 때 따르는 최상위 지침이다.
Claude Code용 원본은 `CLAUDE.md`와 `.claude/**`에 있으며, Codex는 아래 매핑에 따라 같은 정책을 적용한다.

## Role

- Java/Kotlin/Spring 본업 + iOS는 신영역인 1인 풀스택 개발자.
- **불확실한 요구사항은 추측하지 말고 반드시 질문한다.**
- 주석·로그·예외 메시지·Bean Validation 메시지는 **한글**, 코드 식별자는 영문.

## Project Overview

- **KickLog**: 조기축구 데이터 분석 iOS 앱 + Spring 백엔드.
- Tech Stack:
  - iOS 26.4 / SwiftUI / SwiftData / Swift Charts / HealthKit / CoreLocation
  - Kotlin / Spring Boot 4 / PostgreSQL 16 / Flyway / Spring Security (JWT)
  - **호스팅: AWS EC2 + RDS (ap-northeast-2 서울) + Terraform** (ADR-0006)
- Bundle ID: `com.opixxx.kicklog` · GitHub: `opixxx/kicklog` (private)
- Architecture: 1인 사이드 — **구조는 3-tier** (Controller/Service/Repository), 도메인별 패키지 (`auth/user/friend/match/place/venue/stat/common`), **모델링은 DDD-lite** (Rich Aggregate + VO + Ubiquitous Language). 헥사고날 Port/Adapter 강제 X. iOS 는 본 하네스 대상 아님.
  - **세부**: `docs/architecture/{overview,domain-modeling,auth,api-conventions}.md`
  - **결정 근거**: `docs/adr/`
  - **DTO 흐름**: `Request → Command → (Service) → Result → Response` — Entity 직접 노출 금지
  - **iOS 가 1차 SoT** (HealthKit raw + SwiftData), 백엔드는 백업 + 친구 공유 채널

## 하네스: KickLog Backend

> **백엔드 전용 하네스다.** iOS 는 사용자가 Xcode 에서 직접 작업하며, 자동 검증·리뷰·테스트 강제 없음 (UI/API 연동만 동작하면 OK).

**목표:** 구현·버그수정·리팩토링 작업에 대해 Intake → EXEC_PLAN(큰 변경만) → Worktree → 검증 → PR 파이프라인을 유지한다.

**트리거:** 백엔드 소스 변경이 예상되는 작업 시 `.claude/skills/orchestrator/SKILL.md`를 작업 규칙으로 참조. 단순 질문·코드 설명·로그 분석·iOS 작업은 직접 응답.

**진입점:** `bash scripts/start-task.sh <task-name> <type>` — worktree/플랜/포트/로그를 원자적으로 생성.

**Codex 적용 방식:**
- Codex는 `.codex/config.toml`의 hook을 자동 실행한다 (`.codex/README.md` 참조).
- **Hook 스크립트는 Claude Code와 동일** (`tools/hooks/*.sh`) — 단일 진실 원천. 두 도구의 동작이 일관된다.
- `.codex/config.toml`이 로드되려면 사용자가 `~/.codex/config.toml`에서 본 프로젝트를 **trusted** 로 등록해야 한다.

**현재 활성 Hook (Claude Code + Codex 양쪽):**
- `PreToolUse` (Bash): `tools/hooks/guard-bash.sh` — 위험 명령 차단
- `SessionStart`: `tools/hooks/session-context.sh` — 작업 상태 자동 컨텍스트 주입
- `PreToolUse` (Edit/Write): `tools/hooks/enforce-worktree.sh` — main에서 **백엔드** 소스 보호 (iOS 는 보호 대상 아님)
- `PreToolUse` (Edit/Write): `tools/hooks/enforce-plan.sh` — 30줄 이상 백엔드 변경 시 EXEC_PLAN 강제
- `Stop`: `tools/hooks/verify-and-block.sh` — 백엔드 `compileKotlin` + 자가수정 (최대 3회)
- `.githooks/pre-commit`: 백엔드 Kotlin 컴파일 게이트

**Agents (백엔드 전용):**
- `code-reviewer` (Kotlin/Spring) — `skills: [coding-conventions]`
- `backend-test-writer` (Cucumber + JUnit5 + Testcontainers) — `skills: [coding-conventions]`

**Skills:**
- `coding-conventions` (백엔드, agent 사전 로드 전용)
- `/orchestrator` — 백엔드 구현 Phase 0~6 파이프라인 강제 (Intake → EXEC_PLAN → Worktree → 검증 → PR)
- `/pr-guide` — PR 생성
- `/code-review` — PR 자동 리뷰

**Codex 작업 체크리스트 (ATDD 1차 + TDD):**
1. 구현성 요청이면 관련 문서(`docs/PRD.md`, `docs/adr/`, `docs/architecture/`, `docs/spec/test-strategy.md`)와 `.claude/skills/orchestrator/SKILL.md`를 먼저 읽는다.
2. 메인 디렉토리의 `main`에서 백엔드 코드 변경이 필요하면 `bash scripts/start-task.sh <task-name> <type>`로 linked worktree 생성 후 그 worktree에서 작업한다. (iOS 작업은 worktree 불필요)
3. EXEC_PLAN.md 작성 — **30줄 미만의 단순 변경은 면제**, 그 외는 목표·접근·**테스트 케이스**·검증 **4섹션** 필수.
   - 테스트 케이스 섹션은 **(3-A) Gherkin 인수 시나리오 + (3-B) 유스케이스/단위** 2블록.
   - 단, 새 API endpoint / DB 마이그레이션 / 친구 권한 경로는 줄 수와 무관하게 인수 시나리오 1개 이상 필수.
4. **ATDD 1차 + TDD: Red → Green → Refactor** 사이클로 구현:
   - 🔴 RED: `backend-test-writer` 에게 위임 — Cucumber Feature + Step Definition + 통합/단위 테스트 생성 → 실패 확인 (`./gradlew test`)
   - 🟢 GREEN: 최소 구현 → 테스트 통과
   - 🔵 REFACTOR: 중복 제거 + 가독성 → 테스트 여전히 통과
5. 종료 전 최소 검증:
   - 백엔드: `cd backend && ./gradlew check`
   - iOS: 자동 검증 없음 (사용자가 Xcode 에서 수동)
6. 검증 실패 시 원인 수정 + 최대 3회 재검증. 3회 연속 실패하면 `blocked` 상태로 보고한다.

## 자주 쓰는 명령

```bash
# 백엔드
cd infra && docker compose up -d postgres
cd backend && ./gradlew bootRun           # 실행
cd backend && ./gradlew compileKotlin     # 컴파일만
cd backend && ./gradlew check             # test + 정적 검사

# iOS (하네스 대상 아님)
open ios/KickLog.xcodeproj

# 작업 시작 (백엔드)
bash scripts/start-task.sh <task-name> feature|fix|refactor|chore|docs
```

## 참조

- Codex 프로젝트 설정: `.codex/config.toml` · 등록 안내: `.codex/README.md`
- Hook 스크립트 (Claude/Codex 공유): `tools/hooks/*.sh`
- 파이프라인·규칙: `.claude/skills/orchestrator/SKILL.md`
- 코딩 컨벤션 (백엔드): `.claude/skills/coding-conventions/SKILL.md`

## 프로젝트 문서

| 영역 | 경로 |
|---|---|
| 제품 요구 사항 | `docs/PRD.md` |
| **핵심 결정 (ADR)** | `docs/adr/0001-mvp-scope.md` (그 외 ADR-0002+ 후속) |
| API 명세 (예정) | `docs/spec/api-spec.md` |
| **테스트 전략 (SoT)** | `docs/spec/test-strategy.md` — 백엔드 ATDD 1차 (Cucumber) |
| **아키텍처 (코드 레벨)** | `docs/architecture/overview.md` / `domain-modeling.md` (3-tier + DDD-lite) / `auth.md` / `api-conventions.md` |
| 리서치 (예정) | `docs/research/` |
| 작업 플랜 영구본 | `docs/agent/plans/YYYY-MM-DD-<task>.md` |
| 트레젝토리 | `docs/agent/trajectories/YYYY-MM.log` |

## 변경 이력

| 날짜 | 변경 내용 | 사유 |
|---|---|---|
| 2026-05-21 | 초기 작성 (Codex용 AGENTS.md 분리) | Claude Code 전용 훅/스킬 전제를 Codex 작업 규칙으로 변환 |
| 2026-05-21 | `.codex/config.toml` 도입 → Codex hook 자동화 | 수동 체크리스트만으로는 위험 명령 자동 차단 불가. 양쪽 도구가 동일 스크립트 재사용. |
| 2026-05-21 | 단계 2 활성: code-reviewer + coding-conventions + enforce-worktree + pre-commit | 백엔드 코딩 시작 전 인프라. iOS 별도 reviewer/conventions는 단계 3. |
| 2026-05-21 | 단계 3 활성: ios-reviewer + ios-conventions + enforce-worktree iOS 확장 | iOS 코딩 시작 직전 하네스 완비. 백엔드/iOS 리뷰어 분리. |
| 2026-05-21 | 단계 4 활성: orchestrator/pr-guide/code-review skills + backend/ios-test-writer agents + enforce-plan + verify-and-block hooks | 구현 오케스트레이션 파이프라인 완비. EXEC_PLAN 30줄 임계 + 백엔드 compile 자가수정 루프. |
| 2026-05-21 | TDD 도입 — Phase 2 흐름 Red→Green→Refactor, EXEC_PLAN 3섹션 → 4섹션 | KickLog 표준 개발 방식 = TDD. test-writer agent Phase 2 진입 시 자동 위임. |
| 2026-05-21 | **ATDD 1차 채택** — `docs/spec/test-strategy.md` 신설(SoT), backend/ios test-writer 재작성, EXEC_PLAN 테스트 케이스를 (3-A)인수 Gherkin + (3-B)iOS ViewModel + (3-C)유스케이스 3블록. **백엔드 = Cucumber-JVM**, **iOS = ViewModel 통합(UI 미경유)**. | GearShow test-writer 적응 + 그린필드 시점에 도입 비용 최소. 1인 사이드 ROI. |
| 2026-05-21 | **iOS 하네스에서 제거** — ios-reviewer/ios-test-writer/ios-conventions 삭제, orchestrator/code-review/pr-guide/test-strategy/hooks 에서 iOS 분기 제거, enforce-worktree iOS 보호 해제. EXEC_PLAN 테스트 케이스는 (3-A) Gherkin + (3-B) 유스케이스 2블록만. 백엔드 전용 하네스로 정착. | 사용자가 iOS 개발자가 아니라 review/test 자동화 ROI 없음. UI/API 연동만 동작하면 OK. iOS 는 Xcode 에서 직접. |
| 2026-05-22 | **`docs/architecture/` 신설** — overview.md (패키지·레이어·DTO·외부 통합) + auth.md (Apple/Kakao OAuth → JWT, soft delete cron) + api-conventions.md (URL prefix, ErrorCode, GlobalExceptionHandler). | ADR-0003 의 결정은 풍부하나 코드/패키지 레벨 적용 미정 — 에이전트가 매번 ADR 통독해야 했음. 한 페이지로 압축. V1__init.sql ↔ ADR-0003 불일치는 첫 도메인 작업과 함께 정정 (점진적). |
| 2026-05-22 | **`domain-modeling.md` 신설 — 3-tier + DDD-lite 정책 명문화** — 구조(3-tier) ≠ 모델링(DDD) 차원 분리, Anemic vs Rich Aggregate 비교, Ubiquitous Language, Aggregate 규칙 + JPA 함정 회피, Value Object, Domain Service, ACL, Bounded Context, 도입 단계(1~4 MVP/5~6 v1.1), 새 Aggregate 체크리스트, 안티패턴 모음. | "3-tier에서 DDD 가능한가" 질문 — 둘이 독립 차원. 헥사고날 Port/Adapter 없이도 Rich Aggregate + VO + Ubiquitous Language 까지는 도입해서 Service 비대화·Primitive Obsession·도메인 어휘 일관성 확보. |
| 2026-05-22 | **AGENTS.md 본 갱신 — CLAUDE.md 와 일괄 동기화** — ATDD 1차 / iOS 제거 / architecture 4문서 / DDD-lite 정책 / 강제 메커니즘 정정 / Agents·Skills 목록 / 참조 표 일괄 반영. | claude-md-improver 진단에서 AGENTS.md currency 4/15 (심각) — Claude Code 변경을 따라가지 못함. iOS 자산 삭제됐는데 "ios-reviewer 활성" 라인 살아있어 Codex 에서 잘못된 에이전트 호출 위험. |
