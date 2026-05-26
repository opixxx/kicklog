#if DEBUG
import Foundation
import HealthKit
import CoreLocation

// E2E 테스트용 임의 .soccer 워크아웃 시드.
// 같은 GPS 근방의 30분 인터벌 4쿼터 → WorkoutGrouper 가 자동으로 1 Match 로 묶음.
// 릴리즈 빌드에서는 이 파일 자체가 컴파일되지 않는다.
@MainActor
final class DebugWorkoutSeeder {

    // 서울시청 부근. 100m 그룹핑 임계 안쪽 (반경 30m) 으로 흩뿌림.
    private static let baseLatitude: Double = 37.5665
    private static let baseLongitude: Double = 126.9780

    // 한 쿼터 운동 + 휴식 시간.
    private static let quarterDuration: TimeInterval = 15 * 60   // 15분
    private static let restDuration: TimeInterval = 5 * 60       // 5분
    private static let quartersPerMatch = 4

    struct SeedResult {
        let matchStart: Date
        let matchEnd: Date
        let quarterCount: Int
    }

    private let store: HKHealthStore

    init(store: HKHealthStore = HealthKitService.shared.store) {
        self.store = store
    }

    // 시드 메인 진입점 — 매치 1건(4쿼터) 을 HealthKit 에 영속화.
    func seedSingleMatch(endingAt: Date = .now.addingTimeInterval(-15 * 60)) async throws -> SeedResult {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw HealthKitError.notAvailable
        }

        // 매치 종료 시각으로부터 역산. 마지막 쿼터 종료 = endingAt.
        let totalDuration = Self.quarterDuration * Double(Self.quartersPerMatch)
            + Self.restDuration * Double(Self.quartersPerMatch - 1)
        let matchStart = endingAt.addingTimeInterval(-totalDuration)

        for quarter in 0..<Self.quartersPerMatch {
            let qStart = matchStart.addingTimeInterval(
                (Self.quarterDuration + Self.restDuration) * Double(quarter)
            )
            let qEnd = qStart.addingTimeInterval(Self.quarterDuration)
            try await seedOneQuarter(start: qStart, end: qEnd, quarterIndex: quarter)
        }

        return SeedResult(
            matchStart: matchStart,
            matchEnd: endingAt,
            quarterCount: Self.quartersPerMatch
        )
    }

    // MARK: - 쿼터 1개 시드

    private func seedOneQuarter(start: Date, end: Date, quarterIndex: Int) async throws {
        let config = HKWorkoutConfiguration()
        config.activityType = .soccer
        config.locationType = .outdoor

        let builder = HKWorkoutBuilder(healthStore: store, configuration: config, device: .local())
        try await builder.beginCollection(at: start)

        let samples = buildQuantitySamples(start: start, end: end, quarterIndex: quarterIndex)
        try await builder.addSamples(samples)
        try await builder.endCollection(at: end)

        guard let workout = try await builder.finishWorkout() else {
            throw HealthKitError.queryFailed(underlying: NSError(
                domain: "DebugWorkoutSeeder",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "HKWorkoutBuilder.finishWorkout 결과 nil"]
            ))
        }

        // GPS Route 부착 — Grouper 의 100m 임계 검증을 위해 필요.
        let locations = buildRouteLocations(start: start, end: end, quarterIndex: quarterIndex)
        let routeBuilder = HKWorkoutRouteBuilder(healthStore: store, device: .local())
        try await routeBuilder.insertRouteData(locations)
        _ = try await routeBuilder.finishRoute(with: workout, metadata: nil)
    }

    // MARK: - Quantity 샘플 빌드

    private func buildQuantitySamples(
        start: Date, end: Date, quarterIndex: Int
    ) -> [HKQuantitySample] {
        var samples: [HKQuantitySample] = []
        samples.append(contentsOf: heartRateSamples(start: start, end: end, quarterIndex: quarterIndex))
        samples.append(contentsOf: distanceSamples(start: start, end: end))
        samples.append(contentsOf: activeEnergySamples(start: start, end: end))
        samples.append(contentsOf: runningSpeedSamples(start: start, end: end, quarterIndex: quarterIndex))
        return samples
    }

    // 심박수 — 15초 간격. 쿼터가 진행될수록 평균이 약간 올라가도록 패턴 부여.
    private func heartRateSamples(
        start: Date, end: Date, quarterIndex: Int
    ) -> [HKQuantitySample] {
        let type = HKQuantityType(.heartRate)
        let unit = HKUnit.count().unitDivided(by: .minute())
        let interval: TimeInterval = 15
        let baseBPM: Double = 140 + Double(quarterIndex) * 4   // 쿼터별 평균 ↑
        var samples: [HKQuantitySample] = []
        var t = start
        var idx = 0
        while t < end {
            // sinusoidal 변동 + 가끔 피크
            let wave = sin(Double(idx) * 0.25) * 12
            let spike = (idx % 23 == 0) ? 25.0 : 0.0
            let bpm = max(80, min(195, baseBPM + wave + spike))
            samples.append(HKQuantitySample(
                type: type,
                quantity: HKQuantity(unit: unit, doubleValue: bpm),
                start: t,
                end: t
            ))
            t = t.addingTimeInterval(interval)
            idx += 1
        }
        return samples
    }

    // 누적 이동 거리 — 15초 단위로 평균 ~25m (≈ 6 km/h 페이스).
    private func distanceSamples(start: Date, end: Date) -> [HKQuantitySample] {
        let type = HKQuantityType(.distanceWalkingRunning)
        let unit = HKUnit.meter()
        let interval: TimeInterval = 15
        var samples: [HKQuantitySample] = []
        var t = start
        var idx = 0
        while t.addingTimeInterval(interval) <= end {
            // 25m 기본 + 약간의 노이즈 + 가끔 스프린트로 추가
            var meters: Double = 25
            if idx % 7 == 3 { meters += 35 }      // 스프린트와 동기화된 추가 거리
            samples.append(HKQuantitySample(
                type: type,
                quantity: HKQuantity(unit: unit, doubleValue: meters),
                start: t,
                end: t.addingTimeInterval(interval)
            ))
            t = t.addingTimeInterval(interval)
            idx += 1
        }
        return samples
    }

    // 활동 칼로리 — 15초당 ~7 kcal.
    private func activeEnergySamples(start: Date, end: Date) -> [HKQuantitySample] {
        let type = HKQuantityType(.activeEnergyBurned)
        let unit = HKUnit.kilocalorie()
        let interval: TimeInterval = 15
        var samples: [HKQuantitySample] = []
        var t = start
        while t.addingTimeInterval(interval) <= end {
            samples.append(HKQuantitySample(
                type: type,
                quantity: HKQuantity(unit: unit, doubleValue: 7.0),
                start: t,
                end: t.addingTimeInterval(interval)
            ))
            t = t.addingTimeInterval(interval)
        }
        return samples
    }

    // 러닝 속도 — 5초 간격. 평균 10~13 km/h, 매 90초마다 15초 스프린트 구간 (16 km/h).
    // 5초 간격 × 3샘플 = 15초 → WorkoutAnalyzer 의 3초 최소 지속 임계 만족 (스프린트 카운트 됨).
    private func runningSpeedSamples(
        start: Date, end: Date, quarterIndex: Int
    ) -> [HKQuantitySample] {
        let type = HKQuantityType(.runningSpeed)
        let unit = HKUnit.meter().unitDivided(by: .second())
        let interval: TimeInterval = 5
        let sprintMps: Double = 16.5 / 3.6   // km/h → m/s, 14 km/h 임계 위
        let cruiseMps: Double = 11.0 / 3.6
        var samples: [HKQuantitySample] = []
        var t = start
        var idx = 0
        while t < end {
            // 90초 = 18 샘플 주기, 그 중 3샘플 (= 15초) 가 스프린트.
            let mod = idx % 18
            let isSprint = (mod >= 0 && mod < 3)
            let mps = isSprint
                ? sprintMps + Double((quarterIndex + idx) % 2) * 0.3
                : cruiseMps + sin(Double(idx) * 0.4) * 0.7
            samples.append(HKQuantitySample(
                type: type,
                quantity: HKQuantity(unit: unit, doubleValue: max(0.5, mps)),
                start: t,
                end: t
            ))
            t = t.addingTimeInterval(interval)
            idx += 1
        }
        return samples
    }

    // MARK: - GPS Route

    // 같은 운동장 안에서 약간씩 흩어진 좌표. 모든 쿼터가 동일 base 좌표 → grouper 가 1 Match 로 묶음.
    private func buildRouteLocations(
        start: Date, end: Date, quarterIndex: Int
    ) -> [CLLocation] {
        let interval: TimeInterval = 10
        var locations: [CLLocation] = []
        var t = start
        var idx = 0
        // 약 30m 반경 (위도 1° ≒ 111km, 0.0003° ≒ 33m)
        let radius = 0.0003
        while t < end {
            let angle = Double(idx) * 0.7 + Double(quarterIndex) * 0.3
            let lat = Self.baseLatitude + sin(angle) * radius
            let lng = Self.baseLongitude + cos(angle) * radius
            // course/speed 는 HKWorkoutRouteBuilder 가 무시해도 valid 좌표 요건은 horizontalAccuracy > 0.
            locations.append(CLLocation(
                coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lng),
                altitude: 30,
                horizontalAccuracy: 5,
                verticalAccuracy: 5,
                course: angle.truncatingRemainder(dividingBy: 360),
                speed: 3.0,
                timestamp: t
            ))
            t = t.addingTimeInterval(interval)
            idx += 1
        }
        return locations
    }
}
#endif
