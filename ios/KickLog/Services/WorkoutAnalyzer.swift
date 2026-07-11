import Foundation
import HealthKit
import SwiftData

// ADR-0004 D8 + ADR-0012 — HKWorkout raw → 헤드라인 집계.
// 속도 산출: Watch distance 샘플(2~3초 구간)의 거리/duration derive → SpeedMetricsCalculator 정제.
// (축구 워크아웃엔 runningSpeed 샘플·GPS 루트가 없다 — 4년치 실측 export 에서 0개. 기존
//  "runningSpeed 우선" 경로는 실전에서 한 번도 타지 않아 제거. ADR-0012)
// 스프린트: 진입 20 / 이탈 17 km/h 히스테리시스 · 고강도 러닝: 진입 14 / 이탈 12 (ADR-0012).
struct WorkoutMetrics: Equatable {
    var distanceM: Int = 0
    var avgSpeedKmh: Double = 0
    var maxSpeedKmh: Double = 0
    var avgHeartRate: Int = 0
    var maxHeartRate: Int = 0
    var sprintCount: Int = 0
    var highIntensityRunCount: Int = 0
    var speedMetricsAvailable: Bool = false
    var activeEnergyKcal: Int = 0
}

// 쿼터 재분석 결과 — "워크아웃 부재"(시뮬레이터·권한·원본 삭제)와 "데이터 0"(조회 방식/시각 경계)을 구분한다.
enum QuarterReanalyzeResult {
    case workoutNotFound   // HealthKit 에 해당 워크아웃이 없음
    case empty             // 워크아웃은 찾았으나 분석 결과 전부 0
    case filled            // 실제 데이터로 채워짐
}

// MARK: - QuarterWorkout.retrim() / reanalyze() (ADR-0004 D8)

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
            apply(metrics)
        }
        // (HK fetch 실패 시 — 시뮬레이터 시드 데이터 — metrics 는 stale 유지)

        match?.recalculateHeadlineMetrics()
    }

    // 시작/종료 시간은 그대로 두고 metrics 만 HealthKit raw 로 다시 계산한다.
    // 용도: ① import 시점의 HealthKit 동기화 지연으로 0 저장된 쿼터의 사후 복구,
    //      ② 지표 알고리즘 버전업 시 일괄 재분석 (ADR-0012).
    // trim 된 쿼터도 저장된 구간(startedAt...endedAt)으로 분석하므로 trim 이 보존된다.
    func reanalyze(store: HKHealthStore, analyzer: WorkoutAnalyzer) async -> QuarterReanalyzeResult {
        guard let uuid = UUID(uuidString: sourceWorkoutUUID),
              let workout = await fetchWorkout(uuid: uuid, store: store),
              startedAt <= endedAt else {
            return .workoutNotFound
        }
        let metrics = await analyzer.analyze(workout: workout, store: store, range: startedAt...endedAt)
        apply(metrics)
        return metrics != WorkoutMetrics() ? .filled : .empty
    }

    private func apply(_ metrics: WorkoutMetrics) {
        distanceM = metrics.distanceM
        avgSpeedKmh = metrics.avgSpeedKmh
        maxSpeedKmh = metrics.maxSpeedKmh
        avgHeartRate = metrics.avgHeartRate
        maxHeartRate = metrics.maxHeartRate
        sprintCount = metrics.sprintCount
        highIntensityRunCount = metrics.highIntensityRunCount
        speedMetricsAvailable = metrics.speedMetricsAvailable
        activeEnergyKcal = metrics.activeEnergyKcal
        analysisVersion = WorkoutAnalyzer.currentAlgorithmVersion
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

    // 지표 알고리즘 버전 (ADR-0004 D8 의 (C) Hybrid 진화). 정제 규칙·임계가 바뀌면 +1 —
    // analysisVersion 이 뒤처진 쿼터는 reanalyzeOutdatedQuarters() 가 앱 구동 시 일괄 재분석한다.
    // v2: ADR-0012 (정제 파이프라인 + 스프린트 20/17 + 고강도 러닝 + 저밀도 계산 불가 + Watch 소스 필터)
    static let currentAlgorithmVersion = 2

    private let calculator = SpeedMetricsCalculator()

    func analyze(
        workout: HKWorkout,
        store: HKHealthStore,
        range: ClosedRange<Date>? = nil
    ) async -> WorkoutMetrics {
        let start = range?.lowerBound ?? workout.startDate
        let end = range?.upperBound ?? workout.endDate

        async let distanceSamples = fetchDistanceSamples(store: store, start: start, end: end)
        async let energy = totalEnergyKcal(workout: workout, store: store, start: start, end: end)
        async let heartRateSamples = fetchHeartRateSamples(store: store, start: start, end: end)

        // ADR-0012 ① — Watch 소스가 있으면 Watch 샘플만 사용 (iPhone 동시 기록의 거리 이중 집계 방지)
        let distSamples = SampleSourceFilter.primary(await distanceSamples, productType: \.sourceProductType)
        let kcal = await energy
        let hrSamples = await heartRateSamples

        // 거리 합산
        let dist = Int(distSamples.reduce(0.0) { $0 + $1.meters }.rounded())

        // 심박 통계 — MVP 는 simple mean (duration 가중은 v1.1+)
        let bpmUnit = HKUnit.count().unitDivided(by: .minute())
        let bpms = hrSamples.map { $0.quantity.doubleValue(for: bpmUnit) }
        let avgHR = bpms.isEmpty ? 0 : Int((bpms.reduce(0, +) / Double(bpms.count)).rounded())
        let maxHR = Int((bpms.max() ?? 0).rounded())

        // 속도 파생 지표 — 정제 파이프라인 (ADR-0012)
        let speed = calculator.calculate(
            distance: distSamples.map {
                SpeedMetricsCalculator.DistanceSample(
                    start: $0.start.timeIntervalSince(start),
                    duration: $0.end.timeIntervalSince($0.start),
                    meters: $0.meters
                )
            },
            heartRate: hrSamples.map {
                SpeedMetricsCalculator.HeartRateSample(
                    time: $0.startDate.timeIntervalSince(start),
                    bpm: $0.quantity.doubleValue(for: bpmUnit)
                )
            },
            analysisDuration: end.timeIntervalSince(start)
        )

        // 평균 속도 fallback — 유효 샘플이 전무하면 총거리/총시간
        var avgSpeed = speed.avgSpeedKmh
        if avgSpeed == 0, dist > 0 {
            let totalH = max(end.timeIntervalSince(start), 1) / 3600.0
            avgSpeed = (Double(dist) / 1000.0) / totalH
        }

        return WorkoutMetrics(
            distanceM: dist,
            avgSpeedKmh: avgSpeed,
            maxSpeedKmh: speed.maxSpeedKmh,
            avgHeartRate: avgHR,
            maxHeartRate: maxHR,
            sprintCount: speed.sprintCount,
            highIntensityRunCount: speed.highIntensityRunCount,
            speedMetricsAvailable: speed.available,
            activeEnergyKcal: kcal
        )
    }

    // MARK: - 거리 샘플 (구간별 m + start/end + 소스)

    // 한 distance 샘플 = (start, end, m, 소스 기기). 구간 속도 derive 의 입력.
    struct DistanceInterval {
        let start: Date
        let end: Date
        let meters: Double
        let sourceProductType: String?   // "Watch6,7" / "iPhone14,2" — 소스 필터 판정용
    }

    private func fetchDistanceSamples(
        store: HKHealthStore,
        start: Date, end: Date
    ) async -> [DistanceInterval] {
        let type = HKQuantityType(.distanceWalkingRunning)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        let samples = await fetchQuantitySamples(store: store, type: type, predicate: predicate)
        return samples.map { s in
            DistanceInterval(
                start: s.startDate,
                end: s.endDate,
                meters: s.quantity.doubleValue(for: .meter()),
                sourceProductType: s.sourceRevision.productType
            )
        }
    }

    // MARK: - 심박 샘플 (통계 + 스파이크 교차검증 공용)

    private func fetchHeartRateSamples(
        store: HKHealthStore,
        start: Date, end: Date
    ) async -> [HKQuantitySample] {
        let type = HKQuantityType(.heartRate)
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

// MARK: - 알고리즘 버전업 일괄 재분석 (ADR-0012)

extension WorkoutAnalyzer {
    // 재진입 가드 — MainActor 라도 per-quarter await 경계에서 다른 Task(옵저버 import 등)가
    // 끼어들 수 있다. 스윕 자체의 중복 실행만 막는다 (import 와의 인터리브는 recalc 가 idempotent 라 수렴).
    @MainActor private static var isReanalyzing = false

    // 앱 구동 시 analysisVersion 이 뒤처진 쿼터를 전부 재분석한다.
    // HK 원본을 못 찾은 경우의 처리 (리뷰 M1):
    //  - UUID 형식이 아예 아닌 쿼터(서버 복구분 "server-...") → 영원히 못 찾으므로 버전만 올려 재시도 중단.
    //  - 실제 UUID 인데 못 찾음 → 권한 미허용/HK 동기화 지연일 수 있어(read 권한 상태는 프라이버시상
    //    조회 불가) 버전을 유지하고 다음 구동에 재시도. fetch 1회는 싸다.
    static func reanalyzeOutdatedQuarters(
        in context: ModelContext,
        store: HKHealthStore = HKHealthStore()
    ) async {
        guard HKHealthStore.isHealthDataAvailable(), !isReanalyzing else { return }
        isReanalyzing = true
        defer { isReanalyzing = false }

        let current = currentAlgorithmVersion
        let descriptor = FetchDescriptor<QuarterWorkout>(
            predicate: #Predicate { $0.analysisVersion < current }
        )
        guard let outdated = try? context.fetch(descriptor), !outdated.isEmpty else { return }
        print("WorkoutAnalyzer: 지표 알고리즘 v\(current) — 재분석 대상 쿼터 \(outdated.count)건")

        let analyzer = WorkoutAnalyzer()
        var affectedMatches = [PersistentIdentifier: Match]()
        for quarter in outdated {
            let result = await quarter.reanalyze(store: store, analyzer: analyzer)
            if result == .workoutNotFound, UUID(uuidString: quarter.sourceWorkoutUUID) == nil {
                quarter.analysisVersion = current
            }
            if let match = quarter.match {
                affectedMatches[match.persistentModelID] = match
            }
        }
        for match in affectedMatches.values {
            match.recalculateHeadlineMetrics()
        }
        context.saveOrLog(caller: "WorkoutAnalyzer.reanalyzeOutdatedQuarters")
    }
}
