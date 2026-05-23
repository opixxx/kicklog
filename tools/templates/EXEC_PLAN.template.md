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
| 개발 방식 | **TDD (Red → Green → Refactor)** |

---

> **단순화 + TDD 원칙**:
> - 본 템플릿은 GearShow의 8섹션을 KickLog용 **4섹션 + optional**로 축소 (Ralph: "계획은 일회용·짧게")
> - **테스트 케이스 섹션**을 통해 TDD 강제 — 구현 전에 테스트 케이스 명시
> - 30줄 미만의 작은 변경은 EXEC_PLAN 자체가 면제됨 (`enforce-plan.sh`)

## 1. 목표 (Goal)

<TODO: 이 작업의 목표를 1~3문장으로. "왜" 이 변경이 필요한지 포함.>

## 2. 접근 (Approach)

<TODO: 어떤 파일을 어떻게 바꿀지 시그니처 수준으로. 구현 디테일은 코딩 시 결정.
- 변경 대상 파일/패키지
- 핵심 인터페이스·계약 (메서드 시그니처, API 엔드포인트, DB 스키마)
- 트랜잭션 경계 / 권한 / 멱등성 등 양보 불가 규칙
- 외부 의존 변경 (백엔드 API 추가 시 iOS 클라이언트 동기 수정 필요 — 본 하네스 대상 아니므로 사용자가 별도 작업)
>

## 3. 테스트 케이스 (Test Cases) — TDD 핵심

> **🔴 RED 먼저, 🟢 GREEN 다음, 🔵 REFACTOR 마지막**

<TODO: 작성할 테스트를 시나리오 단위로 나열. Happy/Unhappy/Edge 분류.

### Happy Path
- [ ] <테스트 1 — 정상 흐름>
- [ ] <테스트 2 — 정상 흐름>

### Unhappy Path (예외)
- [ ] <테스트 3 — 권한 거부, 인증 실패, 검증 실패 등>
- [ ] <테스트 4 — 외부 API 실패, 네트워크 끊김>

### Edge Cases
- [ ] <테스트 5 — 경계 값, null, 빈 컬렉션, 동시성>
- [ ] <테스트 6 — 멱등성, 재시도, race condition>

### 테스트 작성자 (자동 위임)
- 백엔드 → `backend-test-writer` agent (Cucumber + Testcontainers + JUnit5 + AssertJ)
- iOS → 본 하네스 대상 아님 (사용자가 Xcode 에서 직접)
>

## 4. 검증 (Verification)

<TODO: 완료 조건을 Bash 명령으로 명시. 구체적이어야 한다.

### 자동 검증
- 백엔드: `cd backend && ./gradlew check`
- iOS: 자동 검증 없음 (사용자가 Xcode 에서 수동 빌드)

### 시나리오 검증 (수동)
- <실제 사용자 시나리오: 사용자가 X 누르면 Y가 보임>
- <친구 기능: 친구 A의 데이터가 B에게 정상 노출>

### 커버리지
- 새 코드 커버리지 70% 이상 (전체 평균)
>

---

## (Optional) 위험도 / 롤백

<TODO: Risk = Safe | Caution | Risky | Critical 중 하나. Risky 이상이면 롤백 전략 명시.
- DB 마이그레이션이 있으면 다운그레이드 SQL
- API breaking change면 이전 버전 호환 계획
>

## (Optional) 후속 / 관련 이슈

<TODO: 본 PR 범위 밖이지만 따라오는 작업이 있으면 메모.>

## (Optional) 학습 기록

<TODO: self-heal, Critical 리뷰, 누락 테스트가 있었다면 기록.
- Trigger: self-heal | review-critical | missing-test | production-risk | security | none
- Root cause:
- Prevention:
- Promoted to: docs/agent/learning.md | EXEC_PLAN template | code-reviewer | backend-test-writer | test-strategy | none
>

---

## TDD 작업 흐름

```
1. 위의 "3. 테스트 케이스" 섹션 채우기 (사용자가 결정)
2. 🔴 RED:
   - test-writer agent에게 위 케이스를 코드로 변환 위임
   - ./gradlew test (or Cmd+U) → 모두 실패 확인
3. 🟢 GREEN:
   - 한 케이스씩 최소 구현
   - 테스트 통과
4. 🔵 REFACTOR:
   - 중복 제거, 메서드 분리, 네이밍 정리
   - 테스트 여전히 통과
5. 다음 케이스 반복
6. 모든 케이스 통과 → "4. 검증" 섹션의 명령 실행
7. self-heal/Critical/누락 테스트가 있었으면 학습 기록 판단
8. PR 생성 (/pr-guide)
```

> 완료 시: `상태` 필드를 `done`으로 변경하고 PR 본문에 본 파일 링크 첨부.
