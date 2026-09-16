# ADR-0012: iOS 부분 하네스 적용 — 계획 강제 · worktree 보호 · 컴파일 자가수정

- 상태: 승인 (2026-07-11)
- 관련: ADR-0001 (MVP 스코프·하네스 원칙), CLAUDE.md 하네스 섹션

## 배경

하네스는 지금까지 **백엔드 전용**이었다. iOS 제외의 근거는 "사용자가 Xcode 에서 직접
작업하며, UI/API 연동만 잘 동작하면 OK"였다 (초기 CLAUDE.md).

그러나 GPS 속도 노이즈 정제(`WorkoutAnalyzer` 파이프라인 개선)처럼 **에이전트가 iOS
구현을 통째로 맡는 작업**이 생기면서 제외 근거가 낡았다. 에이전트가 수행하는 iOS 변경은
백엔드와 동일한 위험(계획 없는 대규모 편집, main 직접 수정, 컴파일 깨진 채 종료)을
갖는다.

또한 이력서 검증용 A/B 실험(계획 유무에 따른 토큰 비용 비교)에서 "하네스 적용" 조건을
iOS 작업에 만들 필요가 있었다 — 이 실험이 확장 시점을 앞당긴 직접 계기다.

## 결정

iOS 를 하네스에 **부분 적용**한다. 전체 파이프라인 이식이 아니라 세 가지만:

| 구성요소 | 적용 | 구현 |
|---|---|---|
| 계획 강제 | ✅ | `enforce-plan.sh` — `ios/**/*.swift` 30줄 이상 변경 시 EXEC_PLAN 요구 |
| worktree 보호 | ✅ | `enforce-worktree.sh` — main 에서 `.swift` 직접 수정 차단 |
| 컴파일 자가수정 | ✅ | `verify-and-block.sh` — iOS 변경 시 `xcodebuild build` 센서 (최대 3회) |
| ATDD / 테스트 강제 | ❌ | iOS 는 테스트 인프라 없음 — 별도 결정 전까지 미적용 |
| 자동 코드 리뷰 | ❌ | `code-reviewer` 는 Kotlin/Spring 전용 유지 |

경계 규칙:

- 보호 대상은 `.swift` 만. `xcassets`·`plist`·`pbxproj` 등 비소스 파일은 기존처럼 자유
  (Xcode 가 자동 수정하는 파일들이라 hook 대상으로 부적합).
- **사용자가 Xcode 에서 직접 수정하는 것은 hook 밖이므로 영향 없음** — 이 하네스는
  에이전트 행동만 구속한다.

## 근거

- **컴파일 센서 비용 실측 (2026-07-11)**: `xcodebuild build -destination
  'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO` 기준 콜드 1분 26초,
  증분 2.5초. Stop hook 3회 루프 최악의 경우에도 수 분 이내 — 수용 가능.
- **ATDD 제외**: 백엔드는 Cucumber+Testcontainers 인프라가 이미 있지만 iOS 는 XCTest
  체계가 갖춰지지 않았다. 하네스 확장과 테스트 인프라 구축을 한 번에 하면 변경 반경이
  커지고, 진행 중인 A/B 실험에 교란 변수가 된다.
- **비소스 파일 제외**: Xcode 프로젝트 파일은 툴체인이 수정하는 경우가 많아 차단 시
  오탐이 잦을 것.

## 결과

- 에이전트의 iOS 30줄 이상 변경은 백엔드와 동일하게 Intake → EXEC_PLAN → worktree →
  컴파일 검증 흐름을 탄다.
- CLAUDE.md 하네스 섹션이 "백엔드 전용" → "백엔드 전체 + iOS 부분"으로 갱신됐다.
- A/B 실험 결과(계획 유무 토큰 비용 비교)는 실험 종료 후 별도 ADR 로 기록 예정.
