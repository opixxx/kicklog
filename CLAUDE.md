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

## 하네스: KickLog Backend

> **백엔드 전용 하네스다.** iOS 는 사용자가 Xcode 에서 직접 작업하며, 자동 검증·리뷰·테스트 강제 없음 (UI/API 연동만 잘 동작하면 OK).

**목표:** 구현·버그수정·리팩토링 작업에 대해 Intake → EXEC_PLAN(큰 변경만) → Worktree → 검증 → PR 파이프라인을 유지하여 일관된 품질을 보장한다. (GearShow 하네스의 KickLog 적응판 — `.claude/skills/orchestrator/SKILL.md`)

**트리거:** 백엔드 소스 변경이 예상되는 작업 시 `orchestrator` 스킬 참조. 단순 질문·코드 설명·로그 분석·iOS 작업은 직접 응답.

**진입점:** `bash scripts/start-task.sh <task-name> <type>` — worktree/플랜/포트/로그를 원자적으로 생성.

**강제 메커니즘 (전체 활성):**
- `PreToolUse` (Bash): `guard-bash.sh` — 위험 명령 차단 ✅ (단계 1)
- `SessionStart`: `session-context.sh` — 작업 상태 자동 주입 ✅ (단계 1)
- `PreToolUse` (Edit/Write): `enforce-worktree.sh` — main에서 **백엔드** 소스 보호 (iOS 는 보호 대상 아님) ✅
- `PreToolUse` (Edit/Write): `enforce-plan.sh` — 30줄 이상 백엔드 변경에 EXEC_PLAN 강제 ✅
- `Stop`: `verify-and-block.sh` — 백엔드 compile + 자가수정 루프 (최대 3회) ✅
- `.githooks/pre-commit`: 백엔드 Kotlin compile 게이트 ✅

**Agents (백엔드 전용):**
- `code-reviewer` (Kotlin/Spring) — `memory: project` + `skills: [coding-conventions]`
- `backend-test-writer` (Cucumber + JUnit5 + Testcontainers) — `memory: project` + `skills: [coding-conventions]`

**Skills:**
- `coding-conventions` (백엔드, agent 사전 로드 전용)
- `/orchestrator` (백엔드 구현 파이프라인 강제 — Phase 0~6)
- `/pr-guide` (PR 생성)
- `/code-review` (PR 자동 리뷰)

**Codex 평행 셋업**: `.codex/config.toml`이 **같은 `tools/hooks/*.sh` 스크립트를 재사용**한다. Claude Code든 Codex든 동일한 hook이 자동 발동 — 단일 진실 원천(SoT). 등록 방법은 `.codex/README.md` 참조.

## 자주 쓰는 명령

```bash
# 백엔드
cd infra && docker compose up -d postgres
cd backend && ./gradlew bootRun           # 실행
cd backend && ./gradlew compileKotlin     # 컴파일만 (빠른 검증)
cd backend && ./gradlew check             # test + 정적 검사

# iOS (하네스 대상 아님 — 사용자가 Xcode 에서 직접)
open ios/KickLog.xcodeproj

# 작업 시작 (백엔드)
bash scripts/start-task.sh <task-name> feature|fix|refactor|chore|docs
```

## 작업 원칙 (요약)

- **ATDD 1차 + TDD (백엔드)**: 30줄 이상 백엔드 변경은 EXEC_PLAN의 "테스트 케이스" 섹션부터 채우고 → RED → GREEN → REFACTOR. 세부는 `docs/spec/test-strategy.md` (SoT).
  - 도구: `backend-test-writer` agent — **Cucumber 인수 시나리오 + Testcontainers 통합 + JUnit 단위**
- **iOS 는 하네스 대상 아님** — 사용자가 Xcode 에서 직접 작업. 테스트/리뷰 강제 없음. UI/API 연동이 동작하면 OK.
- **작은 변경은 직접**, 큰 변경은 plan 모드 먼저. 30줄 미만은 EXEC_PLAN + TDD 면제.
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
| **테스트 전략 (SoT)** | `docs/spec/test-strategy.md` — 백엔드 ATDD 1차 (Cucumber) |
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
| 2026-05-21 | 단계 4 활성: orchestrator + pr-guide + code-review skills + test-writer agents (backend/ios) + enforce-plan + verify-and-block hooks | 구현 오케스트레이션 파이프라인 (Phase 0~6) 완비. EXEC_PLAN 30줄 임계 + 백엔드 compile 자가수정 루프. |
| 2026-05-21 | TDD 도입 — Phase 2 흐름 Red→Green→Refactor, EXEC_PLAN 3섹션 → 4섹션 (테스트 케이스 추가), test-writer agent Phase 2 진입 시 자동 위임 | KickLog 표준 개발 방식 = TDD. 사용자 결정. |
| 2026-05-21 | **ATDD 1차 채택** — `docs/spec/test-strategy.md` 신설(SoT), backend-test-writer/ios-test-writer 재작성, EXEC_PLAN 테스트 케이스 섹션을 (3-A)인수 Gherkin + (3-B)iOS ViewModel + (3-C)유스케이스 3블록으로 분리. **백엔드 = Cucumber-JVM**, **iOS = ViewModel 통합(UI 미경유)**. XCUITest 는 사후 스모크만. | GearShow test-writer 적응 + 그린필드 시점에 ATDD 도입 비용 최소. 1인 사이드 ROI 고려해 도구 선택 (Cucumber 풀 vs ViewModel 통합). |
| 2026-05-21 | **iOS 하네스에서 제거** — ios-reviewer/ios-test-writer/ios-conventions 삭제, orchestrator/code-review/pr-guide/test-strategy/hooks 에서 iOS 분기 제거, enforce-worktree iOS 보호 해제. EXEC_PLAN 테스트 케이스는 (3-A) Gherkin + (3-B) 유스케이스 2블록만. 백엔드 전용 하네스로 정착. | 사용자가 iOS 개발자가 아니라 review/test 자동화 ROI 없음. UI/API 연동만 동작하면 OK. iOS 는 Xcode 에서 직접. |
