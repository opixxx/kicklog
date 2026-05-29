# EXEC_PLAN — quarter-max-speed

| 항목 | 값 |
|---|---|
| Task | quarter-max-speed |
| Type | feature |
| Branch | feature/quarter-max-speed |
| Worktree | /Users/opix/Developer/kicklog/.worktrees/quarter-max-speed |
| Port | 9000 |
| 생성 시각 | 2026-05-29 17:20 |
| 상태 | `done` |
| 개발 방식 | 단순 필드 추가 (30줄 미만 백엔드 변경 → ATDD 면제) |

---

## 1. 목표 (Goal)

5/28 실측 + 헬스킷 export 분석 + ADR-0001 D8/D9 개정으로 **쿼터별 최고속도 (maxSpeedKmh)** 가 매치 detail 의 새 "쿼터별 상세 카드" 에서 표시되어야 함. 그런데:

1. 백엔드 `quarter_workouts` 테이블에 `max_speed_kmh` 컬럼이 없어 PUT 시 무시되고 fetch 시 0 반환
2. iOS `MatchDTO.replaceQuarters` 가 백엔드 응답으로 quarter 재생성 시 `maxSpeedKmh` 인자 누락 → default 0

→ 쿼터별 카드의 최고속도가 항상 0 km/h 로 보이는 이슈. 풀스택 정상화 필요.

## 2. 접근 (Approach)

### 백엔드 (이 worktree)
- `V14__quarter_workouts_max_speed.sql` — `max_speed_kmh DOUBLE PRECISION NOT NULL DEFAULT 0` 컬럼 추가 (idempotent ALTER)
- `QuarterWorkout` entity — `maxSpeedKmh: Double = 0.0` 필드
- `UpsertQuarterCommand` — 필드 추가
- `UpsertQuarterRequest` + `toCommand()` — 매핑 (validation `@DecimalMin("0.0")`)
- `QuarterWorkoutResponse` + `from(quarter)` — 매핑
- `Match.replaceQuarters` — Command → Entity 매핑에 `maxSpeedKmh` 포함

### iOS (이 worktree, 같은 PR)
- `MatchDTO.PutQuarterRequest` — `maxSpeedKmh: Double` 필드
- `MatchDTO.QuarterDetailResponse` — `maxSpeedKmh: Double` 필드
- `QuarterWorkout.toPutRequest()` — 매핑
- `Match.replaceQuarters` — `dto.maxSpeedKmh` 사용

### 그 외 같은 PR 으로 묶인 5/28 실측 후속 변경 (iOS + docs)
- `WorkoutGrouper` — D3 GPS 부재 시 시간 임계만으로 매칭 (ADR-0002 revision)
- `WorkoutAnalyzer` — distance 샘플 기반 max/sprint derive + 35 km/h sanity cap
- `Domain.QuarterWorkout` — `maxSpeedKmh` 필드
- `WorkoutImporter` — metrics → quarter 매핑
- `LabelingScreen` — Q1~Q4 4 chip + 시간순 자동 매핑
- `MatchDetailScreen` — 막대그래프 평균속도 → 이동거리 + 쿼터별 상세 카드 6 metric
- `SettingsScreen` — DEBUG 빌드 "내 매치 + anchor 리셋" 버튼
- `ADR-0001 D8` revision (3초 + distance derive + 35 cap)
- `ADR-0001 D9` revision (이동거리 막대 + 쿼터별 상세 카드)
- `ADR-0002 D3` revision (GPS 부재 시 시간만 매칭)

## 3. 테스트 케이스

백엔드 변경 ~15줄 (필드 추가뿐) — **30줄 미만 EXEC_PLAN / ATDD 면제** (`enforce-plan.sh`). 기존 매치 PUT/GET 통합 테스트가 새 필드 default 0 으로 통과.

iOS 는 본 하네스 대상 아님 — 사용자가 시뮬레이터에서 시드 → 라벨링 → 매치 detail 의 쿼터별 카드 최고속도 표시 확인.

## 4. 검증 (Verification)

### 자동 검증
- 백엔드: `cd backend && ./gradlew compileKotlin` → ✅ BUILD SUCCESSFUL (29s)
- iOS: Xcode 시뮬레이터 빌드 + 시드 + 라벨링 + 매치 detail 확인 (사용자 수동)

### 시나리오 검증 (수동)
1. worktree backend 실행 → Flyway V14 자동 적용 (`Migrating schema "public" to version "14"`)
2. 시뮬레이터 KickLog 삭제 후 재설치 → 로그인 → 디버그 시드 → 라벨링 → 매치 detail
3. 쿼터별 상세 카드의 **최고속도 != 0 km/h** (DebugWorkoutSeeder runningSpeed 16.5 km/h 기반)

## (Optional) 위험도 / 롤백

- **Risk: Safe** — 새 컬럼 추가 (NOT NULL DEFAULT 0). 기존 데이터에 default 0 적용. 다운그레이드 SQL: `ALTER TABLE quarter_workouts DROP COLUMN max_speed_kmh;`
- API breaking change 아님 — 클라이언트가 새 필드 안 보내면 default 0, 새 응답 필드 무시하면 안전 (Jackson `ignoreUnknown`).

## (Optional) 후속 / 관련 이슈

- `MatchSummaryResponse` 의 매치 헤드라인 `maxSpeedKmh` 는 이미 V7 에 있어 별도 변경 없음
- iOS 가 더 정확한 `maxSpeedKmh` 를 sync 하기 시작하면 시즌 집계 SQL derive 도 영향 (ADR-0003/0004 D9) — 별도 점검 필요 시 후속 이슈

## (Optional) 학습 기록

- **Trigger**: missing-test (백엔드 ATDD 면제 + iOS 사용자 검증 의존)
- **Root cause**: 풀스택 필드 추가 시 백엔드 DTO 컬럼/iOS 매핑 어느 한쪽 누락하면 silent 0 default → UI 에서 발견되기 전까진 모름
- **Prevention**: 다음 풀스택 필드 추가 시 양쪽 PutRequest/Response 동시 grep 으로 매핑 누락 검출
- **Promoted to**: 본 EXEC_PLAN 의 "접근" 섹션이 체크리스트 역할
