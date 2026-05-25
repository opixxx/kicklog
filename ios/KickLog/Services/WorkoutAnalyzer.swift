import Foundation
import HealthKit

// ADR-0004 D8 + ADR-0001 D8 — HKWorkout raw → 헤드라인 집계.
// 스프린트는 runningSpeed 14 km/h 절대 임계 기반 (ADR-0001 D8 MVP).
struct WorkoutMetrics: Equatable {
    var distanceM: Int = 0
    var avgSpeedKmh: Double = 0
    var avgHeartRate: Int = 0
    var maxHeartRate: Int = 0
    var sprintCount: Int = 0
    var activeEnergyKcal: Int = 0
}

@MainActor
final class WorkoutAnalyzer {

    // 스프린트 임계 — ADR-0001 D8 (14 km/h 절대)
    static let sprintSpeedThresholdKmh: Double = 14.0
    // 스프린트 최소 지속 시간 (잡음 제거) — MVP 휴리스틱 3초
    static let sprintMinDurationSeconds: TimeInterval = 3.0

    func analyze(
        workout: HKWorkout,
        store: HKHealthStore,
        range: ClosedRange<Date>? = nil
    ) async -> WorkoutMetrics {
        let start = range?.lowerBound ?? workout.startDate
        let end = range?.upperBound ?? workout.endDate

        async let distance = totalDistanceMeters(workout: workout, store: store, start: start, end: end)
        async let energy = totalEnergyKcal(workout: workout, store: store, start: start, end: end)
        async let heart = heartRateStats(store: store, start: start, end: end)
        async let speed = speedStats(store: store, start: start, end: end)

        let dist = await distance
        let kcal = await energy
        let (avgHR, maxHR) = await heart
        let (avgSpeed, sprints) = await speed

        // distance / duration 으로 평균 속도 보강 (running speed 없을 때 fallback)
        let durationH = max(end.timeIntervalSince(start), 1) / 3600.0
        let derivedAvgKmh = (Double(dist) / 1000.0) / durationH
        let finalAvgSpeed = avgSpeed > 0 ? avgSpeed : derivedAvgKmh

        return WorkoutMetrics(
            distanceM: dist,
            avgSpeedKmh: finalAvgSpeed,
            avgHeartRate: avgHR,
            maxHeartRate: maxHR,
            sprintCount: sprints,
            activeEnergyKcal: kcal
        )
    }

    // MARK: - 거리 (m)

    private func totalDistanceMeters(
        workout: HKWorkout,
        store: HKHealthStore,
        start: Date, end: Date
    ) async -> Int {
        // workout.totalDistance 는 deprecated — sample fetch 로 합산
        let type = HKQuantityType(.distanceWalkingRunning)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        let samples = await fetchQuantitySamples(store: store, type: type, predicate: predicate)
        let meters = samples.reduce(0.0) { acc, s in
            acc + s.quantity.doubleValue(for: .meter())
        }
        return Int(meters.rounded())
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

    // MARK: - 속도 (평균 km/h + 스프린트 카운트)

    private func speedStats(
        store: HKHealthStore,
        start: Date, end: Date
    ) async -> (avgKmh: Double, sprintCount: Int) {
        let type = HKQuantityType(.runningSpeed)
        let unit = HKUnit.meter().unitDivided(by: .second())
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        let samples = await fetchQuantitySamples(store: store, type: type, predicate: predicate)
        guard !samples.isEmpty else { return (0, 0) }

        // 평균 속도 (km/h)
        let speedsMps = samples.map { $0.quantity.doubleValue(for: unit) }
        let avgMps = speedsMps.reduce(0, +) / Double(speedsMps.count)
        let avgKmh = avgMps * 3.6

        // 스프린트 카운트 — 14 km/h 이상 구간이 3초 이상 지속될 때마다 +1
        let thresholdMps = Self.sprintSpeedThresholdKmh / 3.6
        var sprints = 0
        var currentRunStart: Date? = nil
        for sample in samples.sorted(by: { $0.startDate < $1.startDate }) {
            let mps = sample.quantity.doubleValue(for: unit)
            if mps >= thresholdMps {
                if currentRunStart == nil { currentRunStart = sample.startDate }
                // 끝나면 검사
            } else if let runStart = currentRunStart {
                if sample.startDate.timeIntervalSince(runStart) >= Self.sprintMinDurationSeconds {
                    sprints += 1
                }
                currentRunStart = nil
            }
        }
        // 마지막 run 이 끝나지 않고 종료된 경우
        if let runStart = currentRunStart,
           let last = samples.last,
           last.endDate.timeIntervalSince(runStart) >= Self.sprintMinDurationSeconds {
            sprints += 1
        }

        return (avgKmh, sprints)
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
