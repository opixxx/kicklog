import Foundation

// ADR-0012 — 속도 정제 파이프라인 + 스프린트/고강도 러닝 재설계.
// HealthKit 무의존 순수 로직 (KickLogTests 에서 실측 픽스처로 검증).
//
// 배경: 축구 워크아웃엔 runningSpeed 샘플·GPS 루트가 없어 2~3초 distance 샘플의
// 거리/시간 derive 가 유일한 속도 재료다. GPS 점프 한 방이 비현실적 속도(33~51km/h)를
// 만들므로, 통계 필터(Hampel — 진짜 스프린트도 자름, 기각) 대신 물리 규칙으로 정제한다:
// 사람은 걷다가 한 샘플(2~3초) 만에 최고속도가 될 수 없고, 진짜 질주는 반드시
// 가감속 램프(이웃 샘플의 흔적)를 남긴다. 판별이 애매하면 심박 급등 여부가 최종 심급.

// 속도 파생 지표 묶음. available=false 면 max/sprint/HSR 은 신뢰 불가(UI 에서 숨김).
struct SpeedMetrics: Equatable {
    var available: Bool = false
    var avgSpeedKmh: Double = 0      // available 무관 — 뭉텅이 샘플에서도 거리/시간은 유효
    var maxSpeedKmh: Double = 0
    var sprintCount: Int = 0
    var highIntensityRunCount: Int = 0
}

struct SpeedMetricsCalculator {

    // 입력 시각은 분석 구간 시작 기준 오프셋(초) — Date 변환은 WorkoutAnalyzer 책임.
    struct DistanceSample: Equatable {
        let start: TimeInterval
        let duration: TimeInterval
        let meters: Double
        var end: TimeInterval { start + duration }
        var kmh: Double { duration > 0 ? meters / duration * 3.6 : 0 }
    }

    struct HeartRateSample: Equatable {
        let time: TimeInterval
        let bpm: Double
    }

    // MARK: - 상수 (근거: docs/adr/0012)

    // 인간 한계(~37km/h) 여유 컷 — 초대형 GPS 점프 제거. 이웃 판정에서도 제외(노이즈이므로).
    static let maxRealisticSpeedKmh: Double = 35.0
    // 걷기 속도 상한 — 양옆이 이 미만이면 가감속 램프 없는 순간이동 = 물리적으로 불가능.
    static let walkingSpeedKmh: Double = 7.0
    // 이웃 존재 판정 간격 / 질주(run) 분리 간격
    static let neighborGapSeconds: TimeInterval = 3.0
    static let runGapSeconds: TimeInterval = 3.0
    // 고립 스파이크 판정 대상 하한 (최고속도 왜곡 가능 구간)
    static let spikeCandidateKmh: Double = 18.0
    // 스프린트 = FIFA 25.2km/h 순간속도의 2~3초 평균 보정판. 진입/이탈 분리(히스테리시스).
    static let sprintEnterKmh: Double = 20.0
    static let sprintExitKmh: Double = 17.0
    // 고강도 러닝 = 기존 스프린트 지표(14km/h)의 새 이름
    static let highIntensityEnterKmh: Double = 14.0
    static let highIntensityExitKmh: Double = 12.0
    // 심박 교차검증 — 직전 40초 평균 대비 직후 45초 최대가 +5bpm 이상,
    // 또는 세션 최고 심박의 95% 도달(후반 고심박 상태 보호 — 실측: 27.8km/h 질주가 +3bpm 에 그침).
    static let hrPreWindowSeconds: TimeInterval = 40.0
    static let hrPostWindowSeconds: TimeInterval = 45.0
    static let hrSurgeBpm: Double = 5.0
    static let hrNearMaxRatio: Double = 0.95
    // 저밀도 판정 — 라이브 기록(중앙값 2~3초)과 뭉텅이(383~726초)는 이봉분포로 갈림.
    // 커버리지 하한은 관측 안 된 구간의 스프린트 누락을 막기 위한 정직성 장치.
    static let maxMedianSampleDurationSeconds: TimeInterval = 10.0
    static let minCoverageRatio: Double = 0.3

    // MARK: - 계산

    func calculate(
        distance: [DistanceSample],
        heartRate: [HeartRateSample],
        analysisDuration: TimeInterval
    ) -> SpeedMetrics {
        let samples = distance.filter { $0.duration > 0 }.sorted { $0.start < $1.start }
        // ② 35km/h 초과 컷 — 시계열에서 완전히 제거
        let intervals = samples.filter { $0.kmh <= Self.maxRealisticSpeedKmh }

        let avg = weightedAverageKmh(intervals)

        guard isDensitySufficient(samples, analysisDuration: analysisDuration) else {
            // 저밀도 → 속도 파생 지표는 0 이 아니라 "계산 불가" (avg 만 유효)
            return SpeedMetrics(available: false, avgSpeedKmh: avg)
        }

        let sessionMaxBpm = heartRate.map(\.bpm).max() ?? 0

        var maxKmh = 0.0
        for (idx, itv) in intervals.enumerated() {
            if itv.kmh >= Self.spikeCandidateKmh,
               !isGenuine(at: idx, in: intervals, heartRate: heartRate, sessionMaxBpm: sessionMaxBpm) {
                continue
            }
            maxKmh = max(maxKmh, itv.kmh)
        }

        let sprints = countEpisodes(
            in: intervals, heartRate: heartRate, sessionMaxBpm: sessionMaxBpm,
            enterKmh: Self.sprintEnterKmh, exitKmh: Self.sprintExitKmh
        )
        let highIntensityRuns = countEpisodes(
            in: intervals, heartRate: heartRate, sessionMaxBpm: sessionMaxBpm,
            enterKmh: Self.highIntensityEnterKmh, exitKmh: Self.highIntensityExitKmh
        )

        return SpeedMetrics(
            available: true,
            avgSpeedKmh: avg,
            maxSpeedKmh: maxKmh,
            sprintCount: sprints,
            highIntensityRunCount: highIntensityRuns
        )
    }

    // MARK: - 저밀도 판정

    private func isDensitySufficient(_ samples: [DistanceSample], analysisDuration: TimeInterval) -> Bool {
        guard !samples.isEmpty, analysisDuration > 0 else { return false }
        let durations = samples.map(\.duration).sorted()
        let median = durations[durations.count / 2]
        let coverage = durations.reduce(0, +) / analysisDuration
        return median <= Self.maxMedianSampleDurationSeconds && coverage >= Self.minCoverageRatio
    }

    // MARK: - 평균 (duration 가중)

    private func weightedAverageKmh(_ intervals: [DistanceSample]) -> Double {
        let totalDuration = intervals.reduce(0.0) { $0 + $1.duration }
        guard totalDuration > 0 else { return 0 }
        let weighted = intervals.reduce(0.0) { $0 + $1.kmh * $1.duration }
        return weighted / totalDuration
    }

    // MARK: - 고속 샘플 진위 판정 (규칙 ③④⑤)

    // 반환 true = 진짜 움직임으로 인정. 스파이크 후보(≥18km/h)와 단일 샘플 에피소드에 적용.
    private func isGenuine(
        at idx: Int,
        in intervals: [DistanceSample],
        heartRate: [HeartRateSample],
        sessionMaxBpm: Double
    ) -> Bool {
        let s = intervals[idx]
        let prev = idx > 0 ? intervals[idx - 1] : nil
        let next = idx + 1 < intervals.count ? intervals[idx + 1] : nil
        let prevNear = prev.map { s.start - $0.end <= Self.neighborGapSeconds } ?? false
        let nextNear = next.map { $0.start - s.end <= Self.neighborGapSeconds } ?? false

        // ④ 양옆 이웃 존재 + 둘 다 걷기 속도 → 가감속 램프 없는 고립 스파이크 = 기각
        if prevNear, nextNear {
            return !(prev!.kmh < Self.walkingSpeedKmh && next!.kmh < Self.walkingSpeedKmh)
        }
        // ③ 한쪽 공백이라도 반대쪽에 가감속 흔적(≥걷기 속도) → 램프의 일부 = 유지
        if (prevNear && prev!.kmh >= Self.walkingSpeedKmh) || (nextNear && next!.kmh >= Self.walkingSpeedKmh) {
            return true
        }
        // ⑤ 판별 불가(정지 출발 스프린트와 노이즈가 같은 모양) → 심박 교차검증이 최종 심급
        return heartRateConfirms(at: s.start, heartRate: heartRate, sessionMaxBpm: sessionMaxBpm)
    }

    // 진짜 전력질주라면 직후 심박이 급등하거나 세션 최고 수준에 도달해야 한다.
    // 심박 데이터 부족 시 보수적으로 기각 — 노이즈를 최고속도로 올리는 것보다 낫다.
    private func heartRateConfirms(
        at time: TimeInterval,
        heartRate: [HeartRateSample],
        sessionMaxBpm: Double
    ) -> Bool {
        let pre = heartRate.filter { $0.time >= time - Self.hrPreWindowSeconds && $0.time < time }
        let post = heartRate.filter { $0.time >= time && $0.time <= time + Self.hrPostWindowSeconds }
        guard pre.count >= 2, let postMax = post.map(\.bpm).max() else { return false }
        let preAvg = pre.reduce(0.0) { $0 + $1.bpm } / Double(pre.count)
        // near-max 분기는 직전 평균보다 상승했을 때만 — 심박이 완전히 평탄하면
        // 세션 최고 == 현재 수준이라 규칙이 무의미해진다 (조깅 중 GPS 스파이크 오인 방지).
        return postMax >= preAvg + Self.hrSurgeBpm
            || (postMax >= sessionMaxBpm * Self.hrNearMaxRatio && postMax > preAvg)
    }

    // MARK: - 에피소드 집계 (히스테리시스 + run 분리)

    // 진입 임계로 시작해 이탈 임계 아래로 떨어지거나 샘플 공백(>3초)을 만나면 끝나는
    // 연속 구간 1개 = 1회. 단일 샘플 에피소드는 isGenuine 재판정 (노이즈 한 방 방지).
    private func countEpisodes(
        in intervals: [DistanceSample],
        heartRate: [HeartRateSample],
        sessionMaxBpm: Double,
        enterKmh: Double,
        exitKmh: Double
    ) -> Int {
        var runs: [[Int]] = []
        var current: [Int] = []
        for (idx, itv) in intervals.enumerated() {
            if let last = current.last {
                let gap = itv.start - intervals[last].end
                if gap > Self.runGapSeconds || itv.kmh < exitKmh {
                    runs.append(current)
                    current = itv.kmh >= enterKmh ? [idx] : []
                } else {
                    current.append(idx)
                }
            } else if itv.kmh >= enterKmh {
                current = [idx]
            }
        }
        if !current.isEmpty { runs.append(current) }

        return runs.count { run in
            run.count >= 2 || isGenuine(at: run[0], in: intervals, heartRate: heartRate, sessionMaxBpm: sessionMaxBpm)
        }
    }
}

// MARK: - 소스 필터 (거리 이중 집계 방지 — 규칙 ①)

// iPhone 을 들고 뛰면 Watch 와 iPhone 이 같은 시간대의 거리를 각자 기록한다
// (실측: 겹침 최대 2,406초, iPhone 기여 0.1~1.8km). Watch 소스가 있으면 Watch 만 쓰고,
// 없으면(폰 단독 기록) 전체를 보존한다 — 어차피 단일 소스라 이중 집계가 없다.
enum SampleSourceFilter {
    static func primary<S>(_ samples: [S], productType: (S) -> String? ) -> [S] {
        let watch = samples.filter { productType($0)?.hasPrefix("Watch") ?? false }
        return watch.isEmpty ? samples : watch
    }
}
