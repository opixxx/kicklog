import Foundation
import HealthKit
import SwiftData

// ADR-0004 D8 + ADR-0001 D8 — HKWorkout raw → 헤드라인 집계.
// 스프린트: 14 km/h 절대 임계, 3초 이상 지속 (ADR-0001 D8).
// 속도 산출: runningSpeed 우선, 없으면 distanceWalkingRunning 샘플(2~3초 구간)의 거리/duration derive.
struct WorkoutMetrics: Equatable {
    var distanceM: Int = 0
    var avgSpeedKmh: Double = 0
    var maxSpeedKmh: Double = 0
    var avgHeartRate: Int = 0
    var maxHeartRate: Int = 0
    var sprintCount: Int = 0
    var activeEnergyKcal: Int = 0
}

// MARK: - QuarterWorkout.retrim() (ADR-0004 D8)

@MainActor
extension QuarterWorkout {
    // 시작/종료 시간 조정 → HKWorkout raw 다시 fetch + 해당 range 로 metrics 재계산.
    // 시뮬레이터에서 HK fetch 실패 시 시간 필드만 갱신 (metrics 는 stale — UI 검증용).
    func retrim(
        newStart: Date,
        newEnd: Date,
        store: HKHealthStore,
        analyzer: WorkoutAnalyzer
    ) async {
        startedAt = newStart
        endedAt = newEnd
        durationSeconds = Int(newEnd.timeIntervalSince(newStart))
        trimmed = true

        if let uuid = UUID(uuidString: sourceWorkoutUUID),
           let workout = await fetchWorkout(uuid: uuid, store: store) {
            let metrics = await analyzer.analyze(workout: workout, store: store, range: newStart...newEnd)
            distanceM = metrics.distanceM
            avgSpeedKmh = metrics.avgSpeedKmh
            maxSpeedKmh = metrics.maxSpeedKmh
            avgHeartRate = metrics.avgHeartRate
            maxHeartRate = metrics.maxHeartRate
            sprintCount = metrics.sprintCount
            activeEnergyKcal = metrics.activeEnergyKcal
        }
        // (HK fetch 실패 시 — 시뮬레이터 시드 데이터 — metrics 는 stale 유지)

        match?.recalculateHeadlineMetrics()
    }

    private func fetchWorkout(uuid: UUID, store: HKHealthStore) async -> HKWorkout? {
        await withCheckedContinuation { (continuation: CheckedContinuation<HKWorkout?, Never>) in
            let predicate = HKQuery.predicateForObject(with: uuid)
            let query = HKSampleQuery(
                sampleType: .workoutType(),
                predicate: predicate,
                limit: 1,
                sortDescriptors: nil
            ) { _, samples, _ in
                continuation.resume(returning: samples?.first as? HKWorkout)
            }
            store.execute(query)
        }
    }
}

@MainActor
final class WorkoutAnalyzer {

    // 스프린트 임계 — ADR-0001 D8 (14 km/h 절대, 3초 이상 지속)
    static let sprintSpeedThresholdKmh: Double = 14.0
    static let sprintMinDurationSeconds: TimeInterval = 3.0

    // Sanity cap — 35 km/h 초과는 GPS jump 노이즈로 제외 (인간 한계 ~37 km/h)
    // ADR-0001 D8: distance 샘플 기반 derive 시 짧은 duration 의 GPS jump 가 비현실적 속도 만듦.
    static let maxRealisticSpeedKmh: Double = 35.0

    func analyze(
        workout: HKWorkout,
        store: HKHealthStore,
        range: ClosedRange<Date>? = nil
    ) async -> WorkoutMetrics {
        let start = range?.lowerBound ?? workout.startDate
        let end = range?.upperBound ?? workout.endDate

        async let distanceSamples = fetchDistanceSamples(store: store, start: start, end: end)
        async let energy = totalEnergyKcal(workout: workout, store: store, start: start, end: end)
        async let heart = heartRateStats(store: store, start: start, end: end)
        async let runningSpeedSamples = fetchRunningSpeedSamples(store: store, start: start, end: end)

        let distSamples = await distanceSamples
        let kcal = await energy
        let (avgHR, maxHR) = await heart
        let rsSamples = await runningSpeedSamples

        // 거리 합산
        let dist = Int(distSamples.reduce(0.0) { $0 + $1.meters }.rounded())

        // 속도 통계 — runningSpeed 우선, 부재/부족 시 distance 샘플 기반 derive
        let (avgSpeed, maxSpeed, sprints) = computeSpeedMetrics(
            distanceSamples: distSamples,
            runningSpeedSamples: rsSamples,
            totalDistanceM: dist,
            start: start,
            end: end
        )

        return WorkoutMetrics(
            distanceM: dist,
            avgSpeedKmh: avgSpeed,
            maxSpeedKmh: maxSpeed,
            avgHeartRate: avgHR,
            maxHeartRate: maxHR,
            sprintCount: sprints,
            activeEnergyKcal: kcal
        )
    }

    // MARK: - 속도 통계 (avg / max / sprint)

    // 한 시점의 속도 측정 — runningSpeed 또는 distance 샘플로부터 derive 된 구간 속도.
    private struct SpeedInterval {
        let start: Date
        let end: Date
        let kmh: Double
        var durationSeconds: TimeInterval { end.timeIntervalSince(start) }
    }

    private func computeSpeedMetrics(
        distanceSamples: [DistanceInterval],
        runningSpeedSamples: [HKQuantitySample],
        totalDistanceM: Int,
        start: Date,
        end: Date
    ) -> (avgKmh: Double, maxKmh: Double, sprintCount: Int) {
        // 1) speed interval 시계열 구성 (35 km/h 초과 GPS jump 는 제외)
        let intervals: [SpeedInterval]
        if runningSpeedSamples.count >= 3 {
            // runningSpeed 가 충분 — 그대로 사용
            let unit = HKUnit.meter().unitDivided(by: .second())
            intervals = runningSpeedSamples
                .sorted(by: { $0.startDate < $1.startDate })
                .compactMap { sample in
                    let kmh = sample.quantity.doubleValue(for: unit) * 3.6
                    guard kmh <= Self.maxRealisticSpeedKmh else { return nil }
                    return SpeedInterval(start: sample.startDate, end: sample.endDate, kmh: kmh)
                }
        } else {
            // runningSpeed 부재/부족 — distance 샘플의 (m / duration) 로 derive
            intervals = distanceSamples
                .sorted(by: { $0.start < $1.start })
                .compactMap { d in
                    let dur = d.end.timeIntervalSince(d.start)
                    guard dur > 0 else { return nil }
                    let kmh = (d.meters / dur) * 3.6
                    guard kmh <= Self.maxRealisticSpeedKmh else { return nil }
                    return SpeedInterval(start: d.start, end: d.end, kmh: kmh)
                }
        }

        // 2) 평균 — duration 가중평균. interval 이 없으면 total distance / total duration fallback.
        let totalDuration = intervals.reduce(0.0) { $0 + $1.durationSeconds }
        let avgKmh: Double
        if totalDuration > 0 {
            let weighted = intervals.reduce(0.0) { $0 + $1.kmh * $1.durationSeconds }
            avgKmh = weighted / totalDuration
        } else {
            let totalH = max(end.timeIntervalSince(start), 1) / 3600.0
            avgKmh = (Double(totalDistanceM) / 1000.0) / totalH
        }

        // 3) 최고속도 — interval 중 max
        let maxKmh = intervals.map(\.kmh).max() ?? 0

        // 4) 스프린트 — 14 km/h 이상 연속 구간의 누적 duration ≥ 3초마다 +1
        var sprints = 0
        var runStart: Date? = nil
        var runEnd: Date? = nil
        for itv in intervals {
            if itv.kmh >= Self.sprintSpeedThresholdKmh {
                if runStart == nil { runStart = itv.start }
                runEnd = itv.end
            } else if let s = runStart, let e = runEnd {
                if e.timeIntervalSince(s) >= Self.sprintMinDurationSeconds { sprints += 1 }
                runStart = nil
                runEnd = nil
            }
        }
        // 마지막 run 이 종료 없이 끝난 경우
        if let s = runStart, let e = runEnd,
           e.timeIntervalSince(s) >= Self.sprintMinDurationSeconds {
            sprints += 1
        }

        return (avgKmh, maxKmh, sprints)
    }

    // MARK: - 거리 샘플 (구간별 m + start/end)

    // 한 distance 샘플 = (start, end, m). 구간 속도 derive 의 입력.
    struct DistanceInterval {
        let start: Date
        let end: Date
        let meters: Double
    }

    private func fetchDistanceSamples(
        store: HKHealthStore,
        start: Date, end: Date
    ) async -> [DistanceInterval] {
        let type = HKQuantityType(.distanceWalkingRunning)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        let samples = await fetchQuantitySamples(store: store, type: type, predicate: predicate)
        return samples.map { s in
            DistanceInterval(start: s.startDate, end: s.endDate, meters: s.quantity.doubleValue(for: .meter()))
        }
    }

    private func fetchRunningSpeedSamples(
        store: HKHealthStore,
        start: Date, end: Date
    ) async -> [HKQuantitySample] {
        let type = HKQuantityType(.runningSpeed)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        return await fetchQuantitySamples(store: store, type: type, predicate: predicate)
    }

    // MARK: - 칼로리

    private func totalEnergyKcal(
        workout: HKWorkout,
        store: HKHealthStore,
        start: Date, end: Date
    ) async -> Int {
        let type = HKQuantityType(.activeEnergyBurned)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        let samples = await fetchQuantitySamples(store: store, type: type, predicate: predicate)
        let kcal = samples.reduce(0.0) { acc, s in
            acc + s.quantity.doubleValue(for: .kilocalorie())
        }
        return Int(kcal.rounded())
    }

    // MARK: - 심박수 (평균/최고)

    private func heartRateStats(
        store: HKHealthStore,
        start: Date, end: Date
    ) async -> (avg: Int, max: Int) {
        let type = HKQuantityType(.heartRate)
        let unit = HKUnit.count().unitDivided(by: .minute())
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        let samples = await fetchQuantitySamples(store: store, type: type, predicate: predicate)
        guard !samples.isEmpty else { return (0, 0) }

        // 평균: 샘플 duration 가중 평균이 정확하지만 MVP 는 simple mean
        let values = samples.map { $0.quantity.doubleValue(for: unit) }
        let avg = Int((values.reduce(0, +) / Double(values.count)).rounded())
        let max = Int((values.max() ?? 0).rounded())
        return (avg, max)
    }

    // MARK: - 공통 sample fetch

    private func fetchQuantitySamples(
        store: HKHealthStore,
        type: HKQuantityType,
        predicate: NSPredicate
    ) async -> [HKQuantitySample] {
        await withCheckedContinuation { (continuation: CheckedContinuation<[HKQuantitySample], Never>) in
            let query = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { _, samples, error in
                if let error {
                    print("WorkoutAnalyzer: \(type) fetch 실패 — \(error)")
                    continuation.resume(returning: [])
                    return
                }
                continuation.resume(returning: (samples as? [HKQuantitySample]) ?? [])
            }
            store.execute(query)
        }
    }
}
