# EXEC_PLAN — sprint-metric-redesign

| 항목 | 값 |
|---|---|
| Task | sprint-metric-redesign |
| Type | fix |
| Branch | fix/sprint-metric-redesign |
| Worktree | /Users/opix/orca/workspaces/kicklog/pinfish/.worktrees/sprint-metric-redesign |
| Port | 9000 |
| 생성 시각 | 2026-07-11 12:29 |
| 상태 | `done` — 테스트 18/18 통과, code-reviewer Major 3건 반영 (M1 버전 bump 정책, M2 재진입 가드, M3 ADR 명시) |
| 개발 방식 | **TDD (Red → Green → Refactor)** |

---

## 1. 목표 (Goal)

GPS 노이즈가 최고속도(33 km/h)·스프린트 횟수를 왜곡하는 문제를 확정 설계(2026-07-11 실측 분석,
아티팩트 `c41d9708` 섹션 8)대로 수정한다. 정제 파이프라인(물리 규칙 + 심박 교차검증)으로 가짜 스파이크만
걸러내되 진짜 전력질주(정지 출발 포함)는 보존하고, 스프린트 지표를 FIFA 보정판(20 km/h)으로 재정의하며,
저밀도 데이터(5분 뭉텅이 샘플)는 지표를 숨기고, iPhone+Watch 거리 이중 집계를 제거한다.

**실측 근거** (애플 건강 export, 42개 축구 워크아웃):
- iPhone·Watch 거리 샘플이 같은 시간대 중복 기록 (최대 2,406초 겹침, iPhone 기여 0.1~1.8 km) → 이중 집계 실재
- 샘플 duration 이 이봉분포: 라이브 기록 = 중앙값 3초 vs 뭉텅이 = 383~726초 (2024년 경기도 후자) → 날짜가 아닌 밀도 기준 필요
- 확정 파이프라인 재현 검증 완료: 스프린트 7/13/16 (쿼터별), 심박 기준 "직전 40초 평균 +5 bpm OR 세션 최고심박 95%" 로 아티팩트 판정과 일치

## 2. 접근 (Approach)

**스코프: iOS 전용.** 백엔드는 저장값 `maxOfOrNull` 집계라 수정 불필요(SQL 무관). DTO 확장(HSR 동기화,
nullable 화)은 후속 PR — 계산 불가 시 PUT 은 0 전송(시즌 best 에서 0은 절대 안 이김 → 무해).

### 신규: `ios/KickLog/Services/SpeedMetricsCalculator.swift` (순수 로직 — HealthKit 무의존, 테스트 대상)

```swift
struct SpeedSample { let start: TimeInterval; let end: TimeInterval; let meters: Double }
struct HeartRateSample { let time: TimeInterval; let bpm: Double }
struct SpeedMetrics: Equatable {
    let available: Bool          // 저밀도면 false → maxSpeed/sprint/HSR 숨김
    let avgSpeedKmh: Double      // available 무관 (뭉텅이 샘플에서도 유효)
    let maxSpeedKmh: Double
    let sprintCount: Int
    let highIntensityRunCount: Int
}
struct SpeedMetricsCalculator {
    func calculate(distance: [SpeedSample], heartRate: [HeartRateSample],
                   analysisDuration: TimeInterval) -> SpeedMetrics
}
```

**정제 규칙 (확정 설계 ①~⑤ — 상수로 명시):**
1. 35 km/h 초과 컷 — 시계열에서 제거 (이웃 판정에도 미사용)
2. 고속 후보(≥18 km/h) 스파이크 판정: 양옆 이웃(각 3초 이내 존재)이 둘 다 <7 km/h → 기각
3. 한쪽 공백 + 반대쪽 이웃 ≥7 km/h → 가감속 램프 → 유지
4. 한쪽 이상 공백 + hot 이웃 없음(애매) → **심박 교차검증**: 직전 40초 평균 대비 직후 45초 최대가
   **+5 bpm 이상 OR 세션 최고심박의 95% 이상** → 유지, 아니면 기각. 심박 데이터 부족(pre<2 or post=0) → 기각(보수적)
5. 지표: 최고속도 = 정제 후 max · 스프린트 = 진입 20/이탈 17 히스테리시스, gap>3초 run 분리, 단일 샘플
   에피소드는 2번 판정 재적용 · 고강도 러닝 = 진입 14/이탈 12 동일 방식
6. 저밀도 판정: 샘플 duration 중앙값 >10초 **OR** 커버리지(샘플 duration 합/분석 구간) <30% → `available=false`

### 수정: `ios/KickLog/Services/WorkoutAnalyzer.swift`
- `fetchDistanceSamples` — **소스 필터**: Watch 소스 샘플 존재 시 Watch 만 사용(거리 합산·속도 모두), 부재 시 전체.
  판정 로직은 순수 함수 `primarySourceSamples(_:)` 로 분리해 단위 테스트
- `computeSpeedMetrics` 제거 → `SpeedMetricsCalculator` 호출로 대체 (HR 샘플 전달)
- `WorkoutMetrics` 에 `highIntensityRunCount: Int`, `speedMetricsAvailable: Bool` 추가

### 수정: `ios/KickLog/Models/Domain.swift` + `WorkoutGrouper.swift`
- `QuarterWorkout` / `Match` 에 `highIntensityRunCount: Int = 0`, `speedMetricsAvailable: Bool = true`,
  `analysisVersion: Int = 1` 추가 (SwiftData lightweight — 기본값만 추가라 안전. 현행 버전 상수 = 2)
- `recalculateHeadlineMetrics` — `speedMetricsAvailable` 쿼터만 max/sum 집계, HSR 합산, match 플래그 = any available
- ADR-0004 D8 의 예정된 진화: 앱 구동 시 `analysisVersion < 2` 쿼터 백그라운드 일괄 재분석
  (기존 `reanalyze` 재사용, `workoutNotFound` 면 버전만 올려 재시도 중단)

### 수정: UI (`MatchDetailScreen`, `KLMatchRow`, `FriendMatchDetailScreen` 은 후속)
- `speedMetricsAvailable == false` → 최고속도·스프린트 "—" 표시
- 고강도 러닝 행 추가 (기존 14 km/h 지표의 새 이름 — 스프린트와 나란히)

### 문서
- `docs/adr/0001-mvp-scope.md` D8 — ADR-0012 로 대체됨(superseded) 표기
- 신규 `docs/adr/0012-speed-noise-filtering-and-sprint-redesign.md` — 정제 규칙·임계 근거·심박 기준 dial·기각한 대안(Hampel/MAD)

### 테스트 픽스처 (실데이터)
`ios/KickLogTests/Fixtures/` — 2026-05-28 3쿼터 + 2024-05-01 저밀도 워크아웃의 Watch distance/HR CSV
(세션 scratchpad `validate_pipeline.py` 로 export 에서 추출)

## 3. 테스트 케이스 (Test Cases) — TDD 핵심

> iOS 대상이므로 Cucumber 대신 **Swift Testing** (`KickLogTests` 타깃, 기존 빈 스텁 활용).
> 인수 기준은 실측 픽스처 재현으로 대체 — 레퍼런스 산출값은 `ref_final.py` 로 확정.

### Happy Path (실측 재현 — 인수 테스트 성격)
- [ ] Q1 픽스처 → available, max 28.5±0.05, 스프린트 7, HSR 25 (33.0 스파이크 기각, 28.5 정지출발 램프 유지)
- [ ] Q2 픽스처 → max 34.1 (공백+심박 +15 급등으로 유지), 스프린트 13, HSR 25
- [ ] Q3 픽스처 → max 29.4, 스프린트 16 (후반 고심박 95% 규칙으로 27.8·26.2 유지), HSR 28
- [ ] 정지 출발 단일 샘플 스프린트 (합성: 공백+20.5+공백, HR 급등) → 유지, 스프린트 1
- [ ] 히스테리시스: 연속 [21, 18, 21] → 스프린트 1회 (쪼개지지 않음)
- [ ] 고강도 러닝: 연속 [15, 15.5, 16] → HSR 1, 스프린트 0

### Unhappy Path (노이즈 기각)
- [ ] 고립 스파이크: 인접 [5, 33, 5] → 기각 — max 5, 스프린트 0
- [ ] 35 초과: [10, 51.4, 10] → max 10
- [ ] 공백 옆 스파이크 + 심박 평탄 → 기각
- [ ] 공백 옆 스파이크 + 심박 데이터 없음 → 기각 (보수적)

### Edge Cases
- [ ] gap>3초 분리: 21 → 8초 공백 → 21 → 스프린트 2회
- [ ] 저밀도 실측(2024-05-01, 중앙값 541초) → available=false
- [ ] 커버리지 <30% (뭉텅이 아니어도) → available=false
- [ ] 빈 샘플 → available=false, 전 지표 0
- [ ] 소스 필터: Watch+iPhone 겹침 샘플 → Watch 만 (합산 거리에 iPhone 미포함), Watch 부재 시 전체 사용

### 테스트 작성자
- iOS 순수 로직이므로 본 세션이 직접 작성 (backend-test-writer 는 Kotlin 전용이라 미위임)

## 4. 검증 (Verification)

### 자동 검증
```bash
# iOS 단위 테스트 (핵심 게이트)
xcodebuild test -project ios/KickLog.xcodeproj -scheme KickLog \
  -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:KickLogTests 2>&1 | tail -20
# 백엔드 무변경 확인 (Stop 훅 자동)
cd backend && ./gradlew compileKotlin
```

### 시나리오 검증 (수동 — 사용자, Xcode)
- 2026-05-28 경기 상세: 최고속도 33.0 → 정제값, 스프린트/고강도 러닝 분리 표시
- 2021~2024 뭉텅이 경기: 최고속도·스프린트 "—" 표시
- 앱 재실행 시 구버전 쿼터 자동 재분석 후 목록 갱신

### 커버리지
- `SpeedMetricsCalculator` 분기 전부 테스트 커버 (위 15케이스)

---

## (Optional) 위험도 / 롤백

**Risk = Caution.** SwiftData 필드 추가는 기본값 있는 lightweight 마이그레이션(안전).
재분석은 SwiftData 값만 갱신 — HealthKit 원본 불변이라 언제든 재실행 가능(롤백 = 코드 되돌리고 재분석).
백엔드 스키마·API 무변경.

## (Optional) 후속 / 관련 이슈

- HSR 동기화 + 계산불가 nullable 전파 (백엔드 DTO/엔티티/Flyway + `SeasonStatService.best()` 0 제외 필터) — 별도 PR
- `FriendMatchDetailScreen` HSR 표시 (백엔드 필드 생긴 뒤)
- 임계 20 vs 21 최종 dial — 다음 경기 체감 횟수와 비교 (메모리 기록됨)
- 심박 기준(+5 bpm / 95%) 도 같은 경기에서 함께 검증

## (Optional) 학습 기록

- Trigger: missing-test → 설계 허점 발견 (RED 1건)
- Root cause: 심박 교차검증의 "세션 최고심박 95%" 분기가 **심박이 완전히 평탄한 세션**에서 무의미
  (세션 최고 == 평탄 수준 → 항상 통과 → 조깅 중 GPS 스파이크 오인). 실측 픽스처만으론 안 잡히고
  합성 Unhappy 케이스(`ambiguousSpikeWithFlatHeartRateRejected`)가 잡아냄.
- Prevention: near-max 분기에 "직전 평균보다 상승" 조건 추가. 비율 기반 규칙은 분모가 퇴화하는
  케이스(평탄 데이터)를 합성 테스트로 반드시 커버할 것.
- Promoted to: ADR-0012 D3 본문에 기록

---

## TDD 작업 흐름

1. 픽스처 복사 + `SpeedMetricsCalculatorTests` 작성 → 🔴 RED (타입 부재로 컴파일 실패 → 스텁 후 assert 실패 확인)
2. 🟢 `SpeedMetricsCalculator` 구현 → 픽스처 3종 + 합성 케이스 통과
3. `WorkoutAnalyzer` 통합 (소스 필터 + HR 전달) → 소스 필터 테스트 통과
4. 모델/집계/UI/재분석 반영 → 빌드 통과
5. 🔵 REFACTOR + ADR 문서화
6. PR (/pr-guide)

> 완료 시: `상태` 필드를 `done`으로 변경하고 PR 본문에 본 파일 링크 첨부.
