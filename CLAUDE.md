# CLAUDE.md

## Role

- Java/Kotlin/Spring 본업 + iOS는 신영역인 1인 풀스택 개발자.
- **불확실한 요구사항은 추측하지 말고 반드시 질문한다.**
- 주석·로그·예외 메시지·Bean Validation 메시지는 **한글**, 코드 식별자는 영문.

## Project Overview

- **KickLog**: 조기축구 데이터 분석 iOS 앱 + Spring 백엔드.
- Tech Stack:
  - iOS 17 / SwiftUI / SwiftData / Swift Charts / HealthKit / CoreLocation
  - Kotlin / Spring Boot 4 / PostgreSQL 15 / Flyway / Spring Security (JWT)
- Bundle ID: `com.opixxx.kicklog` · GitHub: `opixxx/kicklog` (private)
- Architecture: 1인 사이드 — MV(SwiftUI Observable) + 단순 Spring 레이어 (Controller/Service/Repository). 헥사고날 강제 X.

## 하네스: KickLog Backend + iOS

**목표:** 구현·버그수정·리팩토링 작업에 대해 Intake → EXEC_PLAN(큰 변경만) → Worktree → 검증 → PR 파이프라인을 유지하여 일관된 품질을 보장한다. (GearShow 하네스의 KickLog 적응판 — `.claude/skills/orchestrator/SKILL.md`)

**트리거:** 소스 변경이 예상되는 작업 시 `orchestrator` 스킬 참조. 단순 질문·코드 설명·로그 분석은 직접 응답.

**진입점:** `bash scripts/start-task.sh <task-name> <type>` — worktree/플랜/포트/로그를 원자적으로 생성.

**강제 메커니즘 (단계적 도입):**
- `PreToolUse` (Bash): `guard-bash.sh` — 위험 명령 차단 (현재 활성)
- `SessionStart`: `session-context.sh` — 현재 작업 상태 자동 주입 (현재 활성)
- `PreToolUse` (Edit/Write): `enforce-worktree.sh`, `enforce-plan.sh` — 단계 2~4에서 도입
- `Stop`: `verify-and-block.sh` — 단계 4에서 도입 (compile만)

**Codex 평행 셋업**: `.codex/config.toml`이 **같은 `tools/hooks/*.sh` 스크립트를 재사용**한다. Claude Code든 Codex든 동일한 hook이 자동 발동 — 단일 진실 원천(SoT). 등록 방법은 `.codex/README.md` 참조.

## 자주 쓰는 명령

```bash
# 백엔드
cd infra && docker compose up -d postgres
cd backend && ./gradlew bootRun           # 실행
cd backend && ./gradlew compileKotlin     # 컴파일만 (빠른 검증)
cd backend && ./gradlew check             # test + 정적 검사

# iOS
open ios/KickLog.xcodeproj
xcodebuild -scheme KickLog -destination 'platform=iOS Simulator,name=iPhone 15' build

# 작업 시작
bash scripts/start-task.sh <task-name> feature|fix|refactor|chore|docs
```

## 작업 원칙 (요약)

- **작은 변경은 직접**, 큰 변경은 plan 모드 먼저. 30줄 미만은 EXEC_PLAN 면제.
- **데이터 정제·분석은 iOS에서** (스프린트 계산·쿼터 통계 등). 백엔드는 저장·공유 책임만.
- **자가수정 우회 금지**: `--no-verify`, `-DskipTests`, `@Disabled` 우회 금지.
- 부수 질문은 `/btw` (도구 액세스 없이 빠른 답변).
- 큰 산출물 격리는 `Explore` 또는 일반 subagent에 위임.

## 참조 (실제 지식 베이스 = docs/)

| 영역 | 경로 |
|---|---|
| 제품 요구 사항 | `docs/PRD.md` |
| **핵심 결정 (ADR)** | `docs/adr/0001-mvp-scope.md` (그 외 ADR-0002+ 후속) |
| API 명세 (예정) | `docs/spec/api-spec.md` |
| 아키텍처 (예정) | `docs/architecture/` |
| 리서치 (예정) | `docs/research/` |
| 작업 플랜 영구본 | `docs/agent/plans/YYYY-MM-DD-<task>.md` |
| 트레젝토리 | `docs/agent/trajectories/YYYY-MM.log` |

## v2 후보 / MVP 스코프 외

- 풋살 모드 (실내, GPS 없는 데이터 모델 분기)
- 자체 watchOS 앱
- 팀 단위 기능 (1:1 친구 → v1.1+)
- ML 기반 분석
- orchestrator 전체 파이프라인 강제 (현재는 권장 수준, 단계 4에서 도입)

## 변경 이력

| 날짜 | 변경 내용 | 사유 |
|---|---|---|
| 2026-05-21 | 초기 작성 (단계 1 하네스 셋업) | grill-me 인터뷰 + GearShow 하네스 적응 |
| 2026-05-21 | `.codex/config.toml` 추가 — Codex hook 자동화 | Codex CLI도 같은 hook 스크립트 자동 실행. 단일 진실 원천 유지. |
