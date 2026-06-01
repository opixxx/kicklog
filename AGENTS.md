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
  - iOS 18.0 / SwiftUI / SwiftData / Swift Charts / HealthKit / CoreLocation
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

**트리거:** 백엔드 소스 변경이 예상되는 작업 시 `.codex/skills/orchestrator/SKILL.md`를 작업 규칙으로 참조. 단순 질문·코드 설명·로그 분석·iOS 작업은 직접 응답.

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
- `docs/agent/learning.md`: self-heal, Critical 리뷰, 누락 테스트를 재발 방지 규칙으로 승격

**Agents (백엔드 전용):**
- `code-reviewer` (Kotlin/Spring) — `skills: [coding-conventions]`
- `backend-test-writer` (Cucumber + JUnit5 + Testcontainers) — `skills: [coding-conventions]`

**Skills:**
- `coding-conventions` (백엔드, agent 사전 로드 전용)
- `/orchestrator` — 백엔드 구현 Phase 0~6 파이프라인 강제 (Intake → EXEC_PLAN → Worktree → 검증 → PR)
- `/pr-guide` — PR 생성
- `/code-review` — PR 자동 리뷰

**Codex 작업 체크리스트 (ATDD 1차 + TDD):**
1. 구현성 요청이면 관련 문서(`docs/PRD.md`, `docs/adr/`, `docs/architecture/`, `docs/spec/test-strategy.md`)와 `.codex/skills/orchestrator/SKILL.md`를 먼저 읽는다.
2. 메인 디렉토리의 `main`에서 백엔드 코드 변경이 필요하면 `bash scripts/start-task.sh <task-name> <type>`로 linked worktree 생성 후 그 worktree에서 작업한다. (iOS 작업은 worktree 불필요)
   - Claude/Codex 모두 스크립트가 기본으로 `.worktrees/<slug>` 내부 worktree를 만든다.
   - worktree 루트의 `EXEC_PLAN.md`는 실파일이 아니라 `docs/agent/plans/YYYY-MM-DD-<slug>.md`를 가리키는 symlink여야 한다.
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
7. 자가수정·Critical 리뷰·누락 테스트가 반복 가능하면 `docs/agent/learning.md`와 관련 agent memory/checklist에 반영한다.

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
- 파이프라인·규칙: `.codex/skills/orchestrator/SKILL.md`
- 코딩 컨벤션 (백엔드): `.codex/skills/coding-conventions/SKILL.md`

## 프로젝트 문서

| 영역 | 경로 |
|---|---|
| 제품 요구 사항 | `docs/PRD.md` |
| **핵심 결정 (ADR)** | `docs/adr/0001-mvp-scope.md` (그 외 ADR-0002+ 후속) |
| **API 명세 (계약)** | `docs/spec/api-spec.md` — 9개 도메인 27 endpoint request/response/에러/예시 |
| **다이어그램** | `docs/spec/diagram.md` — ERD + 인증 시퀀스 (Mermaid) |
| **테스트 전략 (SoT)** | `docs/spec/test-strategy.md` — 백엔드 ATDD 1차 (Cucumber) |
| **아키텍처 (코드 레벨)** | `docs/architecture/overview.md` / `domain-modeling.md` (3-tier + DDD-lite) / `auth.md` / `api-conventions.md` |
| 리서치 (예정) | `docs/research/` |
| 작업 플랜 영구본 | `docs/agent/plans/YYYY-MM-DD-<task>.md` |
| 트레젝토리 | `docs/agent/trajectories/YYYY-MM.log` |
| 학습 저널 | `docs/agent/learning.md` |

## 변경 이력

> 이 파일에 변경 이력을 누적하지 않는다 — `git log` 와 `docs/adr/` 로 추적. (컨텍스트 토큰 절약)
