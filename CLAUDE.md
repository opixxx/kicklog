# CLAUDE.md

## Role

- Java/Kotlin/Spring 본업 + iOS는 신영역인 1인 풀스택 개발자.
- **불확실한 요구사항은 추측하지 말고 반드시 질문한다.**
- 주석·로그·예외 메시지·Bean Validation 메시지는 **한글**, 코드 식별자는 영문.

## Project Overview

- **KickLog**: 조기축구 데이터 분석 iOS 앱 + Spring 백엔드.
- Tech Stack:
  - iOS 18.0 / SwiftUI / SwiftData / Swift Charts / HealthKit / CoreLocation
  - Kotlin / Spring Boot 4 / PostgreSQL 16 / Flyway / Spring Security (JWT)
  - **호스팅: AWS EC2 단일 박스 (t4g.small arm64, ap-northeast-2 서울) + Terraform** — 앱 + Postgres 컨테이너 동거, RDS 폐지 (ADR-0006 → ADR-0016)
- Bundle ID: `com.opixxx.KickLog` · GitHub: `opixxx/kicklog` (private)
- Architecture: 1인 사이드 — **구조는 3-tier** (Controller/Service/Repository), 도메인별 패키지 (`auth/user/friend/match/place/venue/stat/common`), **모델링은 DDD-lite** (Rich Aggregate + VO + Ubiquitous Language). 헥사고날 Port/Adapter 강제 X. iOS 는 본 하네스 대상 아님.
  - **세부**: `docs/architecture/{overview,domain-modeling,auth,api-conventions}.md` (코드 레벨 적용 — ADR 의 how)
  - **결정 근거**: `docs/adr/` (ADR 의 why)
  - **DTO 흐름**: `Request → Command → (Service) → Result → Response` — Entity 직접 노출 금지
  - **모델링**: Aggregate Root 만 Repository, Entity 안에 비즈니스 메서드, `@Embeddable` VO 로 Primitive Obsession 회피 — `domain-modeling.md`
  - **인증**: Apple/Kakao OAuth → 자체 JWT (Access 1h + Refresh 90d, DB 저장) — `auth.md`
  - **에러 응답**: `{ code, message, field?, traceId? }` — `common/exception/ErrorCode` enum 경유, `GlobalExceptionHandler` 단일 진입점
  - **iOS 가 1차 SoT** (HealthKit raw + SwiftData), 백엔드는 백업 + 친구 공유 채널

## 하네스: KickLog

> **백엔드는 전체 파이프라인, iOS 는 부분 적용** (ADR-0012). 에이전트가 iOS 구현을 맡는 경우가 생기면서 iOS 도 계획 강제·worktree 보호·컴파일 자가수정 대상이 됐다. 단 ATDD·자동 리뷰·테스트 강제는 여전히 백엔드 전용 (iOS 는 테스트 인프라 없음). 사용자가 Xcode 에서 직접 수정하는 것은 hook 밖이라 영향 없음.

**목표:** 구현·버그수정·리팩토링 작업에 대해 Intake → EXEC_PLAN(큰 변경만) → Worktree → 검증 → PR 파이프라인을 유지하여 일관된 품질을 보장한다. (GearShow 하네스의 KickLog 적응판 — `.claude/skills/orchestrator/SKILL.md`)

**트리거:** 백엔드 소스 변경이 예상되는 작업 시 `orchestrator` 스킬 참조. 단순 질문·코드 설명·로그 분석·iOS 작업은 직접 응답.

**진입점:** `bash scripts/start-task.sh <task-name> <type>` — worktree/플랜/포트/로그를 원자적으로 생성.
- Claude/Codex 모두 기본 worktree 위치는 `.worktrees/<slug>`이다.
- worktree 루트의 `EXEC_PLAN.md`는 `docs/agent/plans/YYYY-MM-DD-<slug>.md` 상대 symlink다.

**강제 메커니즘 (전체 활성):**
- `PreToolUse` (Bash): `guard-bash.sh` — 위험 명령 차단 ✅ (단계 1)
- `SessionStart`: `session-context.sh` — 작업 상태 자동 주입 ✅ (단계 1)
- `PreToolUse` (Edit/Write): `enforce-worktree.sh` — main에서 백엔드(.kt 등)·iOS(.swift) 소스 보호 ✅
- `PreToolUse` (Edit/Write): `enforce-plan.sh` — 30줄 이상 백엔드·iOS 변경에 EXEC_PLAN 강제 ✅
- `Stop`: `verify-and-block.sh` — 백엔드 compileKotlin / iOS xcodebuild + 자가수정 루프 (최대 3회) ✅
- `.githooks/pre-commit`: 백엔드 Kotlin compile 게이트 ✅
- `docs/agent/learning.md`: self-heal, Critical 리뷰, 누락 테스트를 재발 방지 규칙으로 승격

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
- **iOS 는 부분 하네스** (ADR-0012) — 30줄 이상 변경 시 EXEC_PLAN + worktree + xcodebuild 자가수정 적용. ATDD·자동 리뷰는 미적용 (UI/API 연동이 동작하면 OK). 사용자의 Xcode 직접 수정은 대상 아님.
- **작은 변경은 직접**, 큰 변경은 plan 모드 먼저. 30줄 미만은 EXEC_PLAN + TDD 면제.
- **매 경기 데이터 정제·분석은 iOS에서** (스프린트 계산·쿼터 통계 등). **시즌/월별 집계는 백엔드 SQL derive** (ADR-0004 D9 / ADR-0003 D9.1). 백엔드는 매 경기 저장·공유 + 집계 derive 책임.
- **자가수정 우회 금지**: `--no-verify`, `-DskipTests`, `@Disabled` 우회 금지.
- **학습 승격**: 자가수정·Critical 리뷰·누락 테스트가 반복 가능하면 `docs/agent/learning.md`와 관련 agent memory/checklist에 반영.
- 부수 질문은 `/btw` (도구 액세스 없이 빠른 답변).
- 큰 산출물 격리는 `Explore` 또는 일반 subagent에 위임.

## 참조 (실제 지식 베이스 = docs/)

| 영역 | 경로 |
|---|---|
| 제품 요구 사항 | `docs/PRD.md` |
| **핵심 결정 (ADR)** | `docs/adr/0001-mvp-scope.md` (그 외 ADR-0002+ 후속) |
| **API 명세 (계약)** | `docs/spec/api-spec.md` — 9개 도메인 27 endpoint request/response/에러/예시 |
| **다이어그램** | `docs/spec/diagram.md` — ERD + 인증 시퀀스 (Mermaid) |
| **테스트 전략 (SoT)** | `docs/spec/test-strategy.md` — 백엔드 ATDD 1차 (Cucumber) |
| **아키텍처 (코드 레벨)** | `docs/architecture/overview.md` (패키지·레이어·DTO·외부 통합) / `domain-modeling.md` (3-tier + DDD-lite 정책 — Aggregate·VO·Ubiquitous Language) / `auth.md` (인증) / `api-conventions.md` (REST 규약·ErrorCode) |
| 리서치 (예정) | `docs/research/` |
| 작업 플랜 영구본 | `docs/agent/plans/YYYY-MM-DD-<task>.md` |
| 트레젝토리 | `docs/agent/trajectories/YYYY-MM.log` |
| 학습 저널 | `docs/agent/learning.md` |

## v2 후보 / MVP 스코프 외

- 풋살 모드 (실내, GPS 없는 데이터 모델 분기)
- 자체 watchOS 앱
- 팀 단위 기능 (1:1 친구 → v1.1+)
- ML 기반 분석
- orchestrator 전체 파이프라인 강제 (현재는 권장 수준, 단계 4에서 도입)

## 변경 이력

> 이 파일에 변경 이력을 누적하지 않는다 — `git log` 와 `docs/adr/` 로 추적. (컨텍스트 토큰 절약)
