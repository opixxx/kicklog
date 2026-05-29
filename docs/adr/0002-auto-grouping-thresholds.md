# ADR-0002: 자동 그룹핑 — 시간/위치 임계값

- **Status**: Accepted
- **Date**: 2026-05-21
- **선행 ADR**: ADR-0001 D6 (자동 그룹핑 + 사용자 확정), ADR-0004 D4 (Observer Query Background Delivery)

## Context

ADR-0001 D6에서 "자동 그룹핑 + 사용자 확정 체크박스" 결정. ADR-0004 D4에서 Observer Query로 새 `QuarterWorkout`이 백그라운드 자동 import됨. 

남은 결정: **여러 QuarterWorkout을 어떤 기준으로 같은 Match에 묶을지** 정확한 시간/위치 임계값.

조기축구 도메인 가정:
- 1경기 = **25분 × 4쿼터** (ADR-0001 D4)
- 쿼터 사이 휴식: 일반 5분, 가변 (1~30분)
- 사용자는 출전한 쿼터만 워치 워크아웃 실행 → 1~4개 QuarterWorkout

---

## Decisions

### D1. 시간 임계값 — **90분**

- **선택**: 직전 QuarterWorkout `endedAt` ~ 새 QuarterWorkout `startedAt` 간격이 **90분 이내** = 같은 경기
- **고려한 옵션**: 30분 / 60분 / **90분 (선택)** / 120분
- **이유**:
  - 조기축구 전체 = 25분 × 4쿼터 + 쉬는 시간 ≈ 110~140분 → 1쿼터 종료 후 4쿼터 시작까지 약 75~115분
  - 60분으로는 부족 (긴 휴식 시 분리 위험), 120분은 같은 운동장 오전/오후 두 경기 합쳐질 위험
  - 90분 = 안전한 중간값

### D2. 위치 임계값 — **100m (Haversine)**

- **선택**: 직전 QuarterWorkout의 첫 GPS 좌표 ~ 새 QuarterWorkout의 첫 GPS 좌표 거리가 **100m 이내** = 같은 운동장
- **고려한 옵션**: 50m / **100m (선택)** / 200m
- **이유**:
  - 운동장 크기 ~ 100×60m (축구장 기준) → 같은 운동장 내 이동은 100m 이내
  - 애플워치 GPS 오차 ±3~5m + 첫 좌표가 라커룸 등에서 잡힐 수 있음 → 50m는 너무 엄격
  - 200m는 인접 공원 운동장도 묶일 위험
  - **Haversine 공식** 사용 (iOS `CLLocation.distance(from:)`)

### D3. GPS Route가 없는 경우 — **시간 임계만으로 같은 Match (개정 2026-05-28)**

- HealthKit `HKWorkoutRoute`가 한쪽이라도 없는 경우:
  - 시간 임계(90분) 만족하면 **같은 Match로 묶음**
  - 양쪽 다 GPS 가 있을 때만 100m 거리 검증 (옆 코트 동시간 케이스 방어)
  - 잘못 묶인 경우 라벨링 화면 D5 토글("이 쿼터는 별도 경기")로 분리

**개정 사유 (2026-05-28 실측):**
- Apple Watch **자동 감지** 워크아웃은 `HKWorkoutRoute` 가 거의 항상 비어있음 (수동 시작/종료해도 야간·실내·짧은 워크아웃에서 Route 미생성 빈번)
- 초기 D3("GPS 없으면 새 Match")는 정상 시나리오에서도 매번 분리 → 5/28 테스트에서 1·2·4쿼터가 3개 별도 Match 로 생성됨
- 90분 시간 임계 자체가 충분히 보수적 — 사용자가 90분 안에 다른 운동장에서 또 축구할 확률은 매우 낮음
- 잘못 묶인 케이스는 D5 수동 분리로 폴백 (이미 MVP 에 포함된 안전장치)

### D4. 알고리즘 위치 — **iOS 클라이언트**

- **선택**: 그룹핑은 iOS `WorkoutGrouper`에서 처리. 백엔드는 그룹핑 결과(`Match` + `QuarterWorkout` 묶음)만 받음.
- **이유**:
  - HealthKit raw 데이터는 iOS만 가짐 (ADR-0003 D9: iOS SoT)
  - Observer Query로 import한 직후 즉시 그룹핑
  - 백엔드는 PUT `/matches/:clientMatchId`로 묶인 결과만 받음

### D5. 사용자 수동 재그룹핑 (MVP) — **단순화**

- 라벨링 화면에서 **"이 쿼터는 별도 경기" 토글**만 제공 (MVP)
- v1.1+ 후보:
  - 두 경기 합치기
  - 다른 Match로 쿼터 이동 (drag & drop)

---

## 알고리즘 의사 코드

```swift
@MainActor
class WorkoutGrouper {
    private let timeThresholdSeconds: TimeInterval = 90 * 60       // 90분
    private let distanceThresholdMeters: Double = 100               // 100m
    
    /// 새 QuarterWorkout을 기존 Match에 매핑하거나 새 Match 생성
    func assignToMatch(_ quarter: QuarterWorkout) async {
        if let match = await findCandidateMatch(for: quarter) {
            quarter.match = match
        } else {
            let newMatch = Match(
                clientMatchId: UUID(),
                playedAt: quarter.startedAt,
                totalDistanceM: 0,
                maxSpeedKmh: 0,
                sprintCount: 0,
                avgHeartRate: 0
            )
            modelContext.insert(newMatch)
            quarter.match = newMatch
        }
        quarter.match?.recalculateHeadlineMetrics()
        try? modelContext.save()
    }
    
    private func findCandidateMatch(for quarter: QuarterWorkout) async -> Match? {
        // 라벨링 안 된 + 최근 Match만 후보
        let descriptor = FetchDescriptor<Match>(
            predicate: #Predicate { $0.labeledAt == nil },
            sortBy: [SortDescriptor(\.playedAt, order: .reverse)]
        )
        guard let candidates = try? modelContext.fetch(descriptor) else { return nil }
        
        for match in candidates {
            guard let lastQuarter = match.quarters.max(by: { $0.endedAt < $1.endedAt }) else {
                continue
            }
            
            // 1. 시간 임계
            let timeDelta = quarter.startedAt.timeIntervalSince(lastQuarter.endedAt)
            guard timeDelta >= 0 && timeDelta <= timeThresholdSeconds else { continue }
            
            // 2. 위치 임계 (양쪽 다 GPS 있을 때만 거리 검증, D3 개정)
            let newCoord = await fetchFirstCoord(uuid: quarter.sourceWorkoutUUID)
            let lastCoord = await fetchFirstCoord(uuid: lastQuarter.sourceWorkoutUUID)
            if let newCoord, let lastCoord {
                let distance = newCoord.distance(from: lastCoord)
                guard distance <= distanceThresholdMeters else { continue }
                return match
            }
            
            // GPS 한쪽이라도 부재 — 시간만으로 매칭 (D3 개정)
            return match
        }
        return nil
    }
}
```

---

## 트레이드오프 + 엣지 케이스

| 케이스 | 동작 |
|---|---|
| 정상 4쿼터, 쿼터 사이 5분 휴식 | 모두 같은 Match로 그룹핑 ✅ |
| 부상 체크로 30분 휴식 | 90분 임계 안에 → 같은 Match ✅ |
| 1쿼터만 뛰고 집에 감, 다음 주 같은 운동장 경기 | 시간 임계(1주) 초과 → 별도 Match ✅ |
| 같은 운동장 오전 9시 / 오후 2시 두 경기 | 시간 5시간 차이 → 별도 Match ✅ |
| 옆 코트(50m 떨어진)에서 같은 시간대 경기 | 위치 50m → 100m 이내 → **같은 Match로 잘못 묶일 위험** ⚠️ (드물지만 사용자가 라벨링 시 분리 가능) |
| GPS 권한 거부 / 자동감지 → route 없음 | **시간 임계만으로 같은 Match (D3 개정)** ✅ |
| 첫 좌표가 라커룸 (운동장에서 80m 떨어진) | 두 번째 쿼터부터는 운동장 내 좌표 → 라커룸 좌표와 100m 차이 → 분리 위험 ⚠️ |
| 운동장이 200×100m로 큼 (대형 공원) | 한쪽 끝 ~ 반대쪽 끝 거리 ~ 200m → 동일 경기인데 분리 위험. v1.1에 venue 등록 기반 매칭으로 보완. |

---

## v1.1+ 보완 후보

- **운동장 기반 매칭** — venue가 등록되어 있으면 venue 반경(예: 200m) 우선 매칭
- **사용자 수동 재그룹핑 UI** — 잘못 묶인 쿼터를 다른 Match로 이동
- **두 Match 병합** — 분리됐는데 같은 경기인 경우
- **머신러닝 기반** — 사용자 라벨링 결과를 학습해 개인화 임계값
- **시간대별 휴식 패턴** — 평소 휴식 길이를 학습해 동적 임계값

---

## Consequences

### 긍정
- **알고리즘 단순** — iOS 한 곳에서 처리, 백엔드 영향 없음
- **MVP 시나리오 대부분 커버** — 정상 4쿼터 + 일반 휴식 패턴
- **명확한 임계값** — 코드 상수로 박혀있어 디버깅·테스트 용이
- **자연스러운 폴백** — 매칭 실패 시 새 Match (영구 손실 없음)

### 부정 / 트레이드오프
- **임계값 코드 상수** — 사용자별 조정 X (v1.1+에서 설정 또는 학습)
- **GPS 의존** — route 없으면 매번 별도 Match (사용자 부담)
- **옆 코트 동시간 경기 잘못 묶임** 위험 (드물지만 가능)
- **큰 운동장에서 분리 위험** (라커룸 ↔ 운동장)

### 후속 결정 필요 (이후 ADR)
- 운동장 등록 후 venue-aware 매칭 도입 시 (v1.1)
- 머신러닝 기반 개인화 임계값 (v2+)

---

## Revisions

| 날짜 | 변경 | 사유 |
|---|---|---|
| 2026-05-21 | 초기 작성 | grill-me 인터뷰 D1 (시간 90분 + 위치 100m) |
| 2026-05-28 | D3 개정 — GPS 부재 시 시간만으로 매칭 | 실측 결과 자동감지 워크아웃의 GPS Route 가 거의 항상 비어있어 1·2·4쿼터가 3개 별도 Match 로 생성된 케이스 발생. 90분 임계만으로도 충분히 보수적이라 판단. |
