# EXEC_PLAN — {{TASK}}

| 항목 | 값 |
|---|---|
| Task | {{TASK}} |
| Type | {{TYPE}} |
| Branch | {{BRANCH}} |
| Worktree | {{WT}} |
| Port | {{PORT}} |
| 생성 시각 | {{DATE}} |
| 상태 | `draft` (작성 중) |

---

> **단순화 원칙**: 본 템플릿은 GearShow의 8섹션을 **3섹션 + optional**로 축소한 버전이다. (Ralph: "계획은 일회용·짧게")
> 30줄 미만의 작은 변경은 EXEC_PLAN 자체가 면제된다 (`enforce-plan.sh`).

## 1. 목표 (Goal)

<TODO: 이 작업의 목표를 1~3문장으로. "왜" 이 변경이 필요한지 포함.>

## 2. 접근 (Approach)

<TODO: 어떤 파일을 어떻게 바꿀지 시그니처 수준으로. 구현 디테일은 코딩 시 결정.
- 변경 대상 파일/패키지
- 핵심 인터페이스·계약 (메서드 시그니처, API 엔드포인트, DB 스키마)
- 트랜잭션 경계 / 권한 / 멱등성 등 양보 불가 규칙
- 외부 의존 변경 (백엔드 API 추가 시 iOS 클라이언트 동기 수정 등)
>

## 3. 검증 (Verification)

<TODO: 완료 조건을 Bash 명령으로 명시. 구체적이어야 한다.
- 백엔드: `cd backend && ./gradlew compileKotlin && ./gradlew test`
- iOS: `xcodebuild -scheme KickLog test -destination ...`
- 통합: 실제 시나리오 (사용자가 X 누르면 Y가 보임)
>

---

## (Optional) 위험도 / 롤백

<TODO: Risk = Safe | Caution | Risky | Critical 중 하나. Risky 이상이면 롤백 전략 명시.
- DB 마이그레이션이 있으면 다운그레이드 SQL
- API breaking change면 이전 버전 호환 계획
>

## (Optional) 후속 / 관련 이슈

<TODO: 본 PR 범위 밖이지만 따라오는 작업이 있으면 메모.>

---

> 완료 시: `상태` 필드를 `done`으로 변경하고 PR 본문에 본 파일 링크 첨부.
