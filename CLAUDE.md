# CLAUDE.md

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
- Architecture: 1인 사이드 — MV(SwiftUI Observable) + 단순 Spring 레이어 (Controller/Service/Repository). 헥사고날 강제 X.

## 하네스: KickLog Backend + iOS

**목표:** 구현·버그수정·리팩토링 작업에 대해 Intake → EXEC_PLAN(큰 변경만) → Worktree → 검증 → PR 파이프라인을 유지하여 일관된 품질을 보장한다. (GearShow 하네스의 KickLog 적응판 — `.claude/skills/orchestrator/SKILL.md`)

**트리거:** 소스 변경이 예상되는 작업 시 `orchestrator` 스킬 참조. 단순 질문·코드 설명·로그 분석은 직접 응답.

**진입점:** `bash scripts/start-task.sh <task-name> <type>` — worktree/플랜/포트/로그를 원자적으로 생성.

**강제 메커니즘 (단계적 도입):**
- `PreToolUse` (Bash): `guard-bash.sh` — 위험 명령 차단 ✅
- `SessionStart`: `session-context.sh` — 현재 작업 상태 자동 주입 ✅
- `PreToolUse` (Edit/Write): `enforce-worktree.sh` — main 브랜치 **백엔드 + iOS 소스** 직접 수정 차단 ✅ (단계 2 + 3)
- `.githooks/pre-commit`: 백엔드 Kotlin compile 게이트 ✅ (단계 2). iOS는 Xcode가 컴파일 오류 즉시 표시 + CI 게이트 (v1.1).
- `PreToolUse` (Edit/Write): `enforce-plan.sh` — 30줄 이상 변경에 EXEC_PLAN 강제 (단계 4에서 도입)
- `Stop`: `verify-and-block.sh` — compile + 자가수정 루프 (단계 4에서 도입)

**Agents 및 Skills (단계 2~3 활성):**
- `code-reviewer` agent: 백엔드(Kotlin/Spring) 전용 코드 리뷰 — `memory: project` + `skills: [coding-conventions]`
- `coding-conventions` skill: 백엔드 컨벤션 (한글 주석/로그, DTO, ErrorCode, 메서드 길이 등)
- **`ios-reviewer` agent** (단계 3): iOS(Swift/SwiftUI/SwiftData/HealthKit) 전용 — `memory: project` + `skills: [ios-conventions]`
- **`ios-conventions` skill** (단계 3): iOS 컨벤션 (한글 주석, Swift API Design Guidelines, SwiftUI 패턴, async/await, Apple HIG)

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
| 2026-05-21 | 단계 2 활성: code-reviewer agent + coding-conventions skill + enforce-worktree + pre-commit | 백엔드 코딩 시작 전 인프라 완성. iOS 별도 reviewer는 단계 3. |
| 2026-05-21 | ADR-0006 — AWS EC2 + RDS + Terraform 호스팅 결정 + Terraform 골격 + Dockerfile | 서울 region (카카오 API 최단) + 12개월 Free Tier + 학습 가치. |
| 2026-05-21 | ADR-0004 (SwiftData + HealthKit) 작성 + PRD 4.7 정정 | 본인/친구 모델 분리, 최소 권한 6개, Observer Query Background Delivery, UTC+Local TZ, 친구 캐시 1h TTL, SwiftData 영속 캐시. |
| 2026-05-21 | 단계 3 활성: ios-reviewer agent + ios-conventions skill + enforce-worktree iOS 확장 | iOS 코딩 시작 직전 하네스 완비. 백엔드/iOS 리뷰어 분리. |
