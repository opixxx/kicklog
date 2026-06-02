---
name: project-loadtest-harness-schema
description: loadtest 하네스 시드가 INSERT 하는 users/matches/quarter_workouts 실제 컬럼 (마이그레이션 누적 반영)
metadata:
  type: project
---

loadtest 하네스 `LoadTestSeedService` 가 raw JDBC 로 INSERT 할 때 참고할 **HEAD 시점 실제 컬럼** (마이그레이션 V1~V14 누적 후):

- `users`: id, apple_user_id(nullable, V2), display_name(NOT NULL), email(nullable), created_at, updated_at, deleted_at(nullable). **username 은 V3 에서 DROP, hide_heart_rate 는 V11 에서 DROP** — INSERT 에 넣으면 깨짐. `display_name` 활성 사용자 UNIQUE(V12) 라 시드 시 고유값 필요.
- `matches`: user_id, client_match_id(uuid, UNIQUE per user), venue_id(NOT NULL FK→venues), played_at, opponent, result(W/D/L nullable), position, goals, assists, opponent_goals(nullable), team_goals(nullable), total_distance_m, max_speed_kmh, sprint_count, avg_heart_rate, created_at, updated_at. **CHECK: team_goals>=goals, team_goals>=0**.
- `quarter_workouts`: match_id(FK), quarter_number(UNIQUE per match), health_kit_workout_id(NOT NULL), started_at, ended_at, duration_seconds, distance_m, avg_speed_kmh, max_speed_kmh, avg_heart_rate, max_heart_rate, sprint_count, active_energy_kcal.
- matches 는 venue_id NOT NULL FK 라 시드는 venue 도 먼저 만들어야 한다 (또는 venue 시드 포함).

**invariant**: `matches.result` 는 `MatchResultType.derive(team_goals, opponent_goals)?.name` 과 일치해야 한다 (`match/service/MatchTypes.kt`). 한쪽 null 이면 result null.

**Why:** EXEC_PLAN(2026-06-02 loadtest-api-harness)이 빈 테이블로는 인덱스·집계 병목이 안 드러나서 현실 규모 시드를 요구. 통합 테스트가 이 컬럼/invariant 를 검증한다.

**How to apply:** 시드 통합 테스트는 Testcontainers 실제 Postgres 로 행 수 + result==derive 검증. 컬럼 추가/삭제 마이그레이션이 생기면 이 메모 갱신.

관련: [[project-acceptance-test-convention]]
