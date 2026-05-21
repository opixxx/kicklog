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
  - iOS 17 / SwiftUI / SwiftData / HealthKit / CoreLocation
  - Kotlin / Spring Boot 4 / PostgreSQL 15 / Flyway / Spring Security (JWT)
- Bundle ID: `com.opixxx.kicklog`
- Architecture: MV (SwiftUI Observable) + 단순 Spring 레이어. 헥사고날 강제 X.

## 하네스: KickLog Backend + iOS

**목표:** 구현·버그수정·리팩토링 작업에 대해 Intake → EXEC_PLAN(큰 변경만) → Worktree → 검증 → PR 파이프라인을 유지한다.

**트리거:** 소스 변경이 예상되는 작업 시 `.claude/skills/orchestrator/SKILL.md`를 작업 규칙으로 참조. 단순 질문·코드 설명·로그 분석은 직접 응답.

**진입점:** `bash scripts/start-task.sh <task-name> <type>` — worktree/플랜/포트/로그를 원자적으로 생성.

**Codex 적용 방식:**
- Codex는 Claude Code의 `.claude/settings.json` 훅을 자동 실행하지 않는다.
- 대신 이 AGENTS.md를 기준으로 동일한 절차를 수동으로 강제한다.
- 소스 변경 전에는 worktree와 EXEC_PLAN 상태를 확인한다.
- 작업 종료 전에 계산적 검증 명령을 직접 실행하고 실패 시 자가수정한다.
- 훅 스크립트는 정책의 실행 가능한 명세로 취급한다. 필요하면 내용을 읽어 같은 판단을 적용한다.

**Claude Code 강제 메커니즘 (참고):**
- `PreToolUse` (Bash): `tools/hooks/guard-bash.sh` — 위험 명령 차단 (현재 활성)
- `SessionStart`: `tools/hooks/session-context.sh` — 작업 상태 주입 (현재 활성)
- `PreToolUse` (Edit/Write): `enforce-worktree.sh`, `enforce-plan.sh` — 단계 2~4 도입 예정
- `Stop`: `verify-and-block.sh` — 단계 4 도입 예정

**Codex 수동 체크리스트:**
1. 구현성 요청이면 관련 문서(`docs/PRD.md`, `docs/adr/`)와 `.claude/skills/orchestrator/SKILL.md`를 먼저 읽는다.
2. 현재 위치가 메인 작업 디렉토리의 `main`이고 코드 변경이 필요하면 `bash scripts/start-task.sh <task-name> <type>`로 linked worktree를 만든 뒤 그 worktree에서 작업한다.
3. EXEC_PLAN.md가 필요한지 판단 — **30줄 미만의 단순 변경은 면제**, 그 외는 필수.
4. Bash 실행 전 `tools/hooks/guard-bash.sh`의 차단 패턴에 해당하는 위험 명령은 실행하지 않는다.
5. 종료 전 최소 검증:
   - 백엔드: `cd backend && ./gradlew compileKotlin`
   - iOS: `xcodebuild -scheme KickLog build` (의존성에 영향 있을 때만)
6. 검증 실패 시 원인을 수정하고 최대 3회까지 재검증한다. 3회 연속 실패하면 `blocked` 상태로 보고한다.

## 자주 쓰는 명령

```bash
cd infra && docker compose up -d postgres
cd backend && ./gradlew bootRun
cd backend && ./gradlew compileKotlin
cd backend && ./gradlew check
open ios/KickLog.xcodeproj
bash scripts/start-task.sh <task-name> feature|fix|refactor|chore|docs
```

## 참조

- 파이프라인·규칙: `.claude/skills/orchestrator/SKILL.md` (단계 4에서 도입)
- 코딩 컨벤션: `.claude/skills/coding-conventions/SKILL.md` (단계 2에서 도입)

## 프로젝트 문서

| 영역 | 경로 |
|---|---|
| 제품 요구 사항 | `docs/PRD.md` |
| **핵심 결정 (ADR)** | `docs/adr/0001-mvp-scope.md` |
| API 명세 (예정) | `docs/spec/api-spec.md` |
| 아키텍처 (예정) | `docs/architecture/` |
| 작업 플랜 영구본 | `docs/agent/plans/YYYY-MM-DD-<task>.md` |

## 변경 이력

| 날짜 | 변경 내용 | 사유 |
|---|---|---|
| 2026-05-21 | 초기 작성 (Codex용 AGENTS.md 분리) | Claude Code 전용 훅/스킬 전제를 Codex 작업 규칙으로 변환 |
