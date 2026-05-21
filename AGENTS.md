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
  - iOS 26.4 / SwiftUI / SwiftData / HealthKit / CoreLocation
  - Kotlin / Spring Boot 4 / PostgreSQL 16 / Flyway / Spring Security (JWT)
  - **호스팅: AWS EC2 + RDS (서울) + Terraform** (ADR-0006)
- Bundle ID: `com.opixxx.kicklog`
- Architecture: MV (SwiftUI Observable) + 단순 Spring 레이어. 헥사고날 강제 X.

## 하네스: KickLog Backend + iOS

**목표:** 구현·버그수정·리팩토링 작업에 대해 Intake → EXEC_PLAN(큰 변경만) → Worktree → 검증 → PR 파이프라인을 유지한다.

**트리거:** 소스 변경이 예상되는 작업 시 `.claude/skills/orchestrator/SKILL.md`를 작업 규칙으로 참조. 단순 질문·코드 설명·로그 분석은 직접 응답.

**진입점:** `bash scripts/start-task.sh <task-name> <type>` — worktree/플랜/포트/로그를 원자적으로 생성.

**Codex 적용 방식:**
- Codex는 `.codex/config.toml`의 hook을 자동 실행한다 (`.codex/README.md` 참조).
- **Hook 스크립트는 Claude Code와 동일** (`tools/hooks/*.sh`) — 단일 진실 원천. 두 도구의 동작이 일관된다.
- `.codex/config.toml`이 로드되려면 사용자가 `~/.codex/config.toml`에서 본 프로젝트를 **trusted** 로 등록해야 한다.

**현재 활성 Hook (Claude Code + Codex 양쪽):**
- `PreToolUse` (Bash): `tools/hooks/guard-bash.sh` — 위험 명령 차단
- `SessionStart`: `tools/hooks/session-context.sh` — 작업 상태 자동 컨텍스트 주입
- `PreToolUse` (Edit/Write): `tools/hooks/enforce-worktree.sh` — main 브랜치 **백엔드 + iOS** 소스 직접 수정 차단 ✅ (단계 2 + 3)
- `.githooks/pre-commit`: 백엔드 Kotlin 컴파일 게이트 ✅ (단계 2)

**향후 도입 예정 (단계 4):**
- `PreToolUse` (Edit/Write): `enforce-plan.sh` — EXEC_PLAN 강제 (단계 4)
- `Stop`: `verify-and-block.sh` (compile + 자가수정 루프) (단계 4)

**Codex 작업 체크리스트:**
1. 구현성 요청이면 관련 문서(`docs/PRD.md`, `docs/adr/`)와 `.claude/skills/orchestrator/SKILL.md`(단계 4 도입 후)를 먼저 읽는다.
2. 메인 디렉토리의 `main`에서 코드 변경이 필요하면 `bash scripts/start-task.sh <task-name> <type>`로 linked worktree 생성 후 그 worktree에서 작업한다.
3. EXEC_PLAN.md 작성 — **30줄 미만의 단순 변경은 면제**, 그 외는 목표·접근·검증 3섹션 필수.
4. 종료 전 최소 검증:
   - 백엔드: `cd backend && ./gradlew compileKotlin`
   - iOS: `xcodebuild -scheme KickLog build` (의존성에 영향 있을 때만)
5. 검증 실패 시 원인 수정 + 최대 3회 재검증. 3회 연속 실패하면 `blocked` 상태로 보고한다.

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

- Codex 프로젝트 설정: `.codex/config.toml` · 등록 안내: `.codex/README.md`
- Hook 스크립트 (Claude/Codex 공유): `tools/hooks/*.sh`
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
| 2026-05-21 | `.codex/config.toml` 도입 → Codex hook 자동화 | 수동 체크리스트만으로는 위험 명령 자동 차단 불가. 양쪽 도구가 동일 스크립트 재사용. |
| 2026-05-21 | 단계 2 활성: code-reviewer + coding-conventions + enforce-worktree + pre-commit | 백엔드 코딩 시작 전 인프라. iOS 별도 reviewer/conventions는 단계 3. |
| 2026-05-21 | 단계 3 활성: ios-reviewer + ios-conventions + enforce-worktree iOS 확장 | iOS 코딩 시작 직전 하네스 완비. 백엔드/iOS 리뷰어 분리. |
