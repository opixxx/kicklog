# Backend Test Writer Memory

누락됐던 테스트 유형과 회귀 케이스를 누적한다.

## Usage

- 구현 후 발견된 누락 테스트, self-heal로 드러난 테스트 공백을 기록한다.
- 다음 RED 단계에서 EXEC_PLAN의 테스트 케이스와 대조한다.
- 프로젝트 전체 규칙으로 승격할 내용은 `docs/spec/test-strategy.md` 또는 agent 지침에 반영한다.

## Project facts

- [인수 테스트 컨벤션](project_acceptance_test_convention.md) — 실제는 Cucumber 아님, MockMvc *AcceptanceTest.kt + (loadtest/prod 는 Testcontainers 필수)
- [loadtest 시드 스키마](project_loadtest_harness_schema.md) — users/matches/quarter_workouts HEAD 컬럼 + result==derive invariant

## Patterns

- [transactionTemplate RED 충돌](pattern_transaction_template_red_conflict.md) — 침묵 fallback 을 명시 실패로 바꾸면 그 fallback 의존 기존 단위 테스트가 GREEN 에서 깨짐

<!--
### YYYY-MM-DD — <pattern>
- Missing case:
- Test to add:
- Prevention:
-->
