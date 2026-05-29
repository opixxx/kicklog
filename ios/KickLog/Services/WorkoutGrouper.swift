import Foundation
import HealthKit
import CoreLocation
import SwiftData

// ADR-0002 — 90분 시간 임계 + 100m 위치 임계로 QuarterWorkout 들을 Match 에 묶는다.
// D3 (2026-05-28 개정): 한쪽이라도 GPS Route 가 없으면 시간 임계만으로 같은 Match 에 묶는다.
// (자동감지 워크아웃은 GPS Route 가 거의 항상 비어있어 기존 보수 정책은 매번 새 Match 만 만들었음)
// 잘못 묶인 경우 라벨링 화면의 "이 쿼터는 별도 경기" 토글(D5)로 분리.
@MainActor
final class WorkoutGrouper {
    // ADR-0002 D1/D2 임계값
    static let timeThresholdSeconds: TimeInterval = 90 * 60
    static let distanceThresholdMeters: Double = 100

    private let modelContext: ModelContext
    private let store: HKHealthStore

    init(modelContext: ModelContext, store: HKHealthStore = HKHealthStore()) {
        self.modelContext = modelContext
        self.store = store
    }

    // 새 QuarterWorkout 을 기존 미라벨링 Match 에 매핑하거나 신규 생성.
    func assignToMatch(_ quarter: QuarterWorkout) async {
        if let match = await findCandidateMatch(for: quarter) {
            quarter.match = match
        } else {
            let newMatch = Match(playedAt: quarter.startedAt)
            modelContext.insert(newMatch)
            quarter.match = newMatch
        }
        quarter.match?.recalculateHeadlineMetrics()
    }

    // MARK: - Candidate 탐색

    private func findCandidateMatch(for quarter: QuarterWorkout) async -> Match? {
        let descriptor = FetchDescriptor<Match>(
            predicate: #Predicate { $0.labeledAt == nil },
            sortBy: [SortDescriptor(\.playedAt, order: .reverse)]
        )
        guard let candidates = try? modelContext.fetch(descriptor) else { return nil }

        // 새 quarter 의 첫 GPS 좌표 (있을 때만)
        let newLocation = await firstLocation(forWorkoutUUID: quarter.sourceWorkoutUUID)

        for candidate in candidates {
            // 1) 시간 임계 — 직전 quarter.endedAt ~ 새 quarter.startedAt
            guard let mostRecentEnd = candidate.quarters.map(\.endedAt).max() else { continue }
            let gap = quarter.startedAt.timeIntervalSince(mostRecentEnd)
            guard gap >= 0 && gap <= Self.timeThresholdSeconds else { continue }

            // 2) 위치 임계 — 양쪽 다 GPS 가 있을 때만 거리로 검증
            if let newLocation, let candidateLocation = await firstLocationForMatch(candidate) {
                let distance = newLocation.distance(from: candidateLocation)
                if distance <= Self.distanceThresholdMeters {
                    return candidate
                }
                // GPS 양쪽 다 있는데 100m 초과 → 다른 운동장
                continue
            }

            // D3 (개정): 한쪽이라도 GPS 부재 — 시간 임계만 통과해도 같은 Match.
            // 잘못 묶이면 라벨링 화면 D5 토글로 사용자가 분리.
            return candidate
        }
        return nil
    }

    // MARK: - HKWorkoutRoute → 첫 GPS 좌표

    private func firstLocationForMatch(_ match: Match) async -> CLLocation? {
        // 시간순으로 정렬된 첫 quarter
        guard let firstQuarter = match.quarters.sorted(by: { $0.startedAt < $1.startedAt }).first else { return nil }
        return await firstLocation(forWorkoutUUID: firstQuarter.sourceWorkoutUUID)
    }

    private func firstLocation(forWorkoutUUID uuidString: String) async -> CLLocation? {
        guard let uuid = UUID(uuidString: uuidString) else { return nil }
        guard let workout = await fetchWorkout(uuid: uuid) else { return nil }
        return await fetchFirstRouteLocation(for: workout)
    }

    private func fetchWorkout(uuid: UUID) async -> HKWorkout? {
        let predicate = HKQuery.predicateForObject(with: uuid)
        return await withCheckedContinuation { (continuation: CheckedContinuation<HKWorkout?, Never>) in
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

    private func fetchFirstRouteLocation(for workout: HKWorkout) async -> CLLocation? {
        // 1. workout 에 연결된 HKWorkoutRoute 페치
        let routes: [HKWorkoutRoute] = await withCheckedContinuation { continuation in
            let predicate = HKQuery.predicateForObjects(from: workout)
            let query = HKSampleQuery(
                sampleType: HKSeriesType.workoutRoute(),
                predicate: predicate,
                limit: 1,
                sortDescriptors: nil
            ) { _, samples, _ in
                continuation.resume(returning: (samples as? [HKWorkoutRoute]) ?? [])
            }
            store.execute(query)
        }
        guard let route = routes.first else { return nil }

        // 2. Route 의 첫 CLLocation
        return await withCheckedContinuation { (continuation: CheckedContinuation<CLLocation?, Never>) in
            var firstLocation: CLLocation?
            let query = HKWorkoutRouteQuery(route: route) { _, locations, done, _ in
                if firstLocation == nil, let loc = locations?.first {
                    firstLocation = loc
                }
                if done {
                    continuation.resume(returning: firstLocation)
                }
            }
            store.execute(query)
        }
    }
}

// MARK: - Match 헤드라인 재계산 (ADR-0004 D8)

extension Match {
    func recalculateHeadlineMetrics() {
        guard !quarters.isEmpty else { return }
        totalDistanceM = quarters.reduce(0) { $0 + $1.distanceM }
        // 진짜 최고속도 — 각 쿼터의 구간별 max 중 max (단일 쿼터에서도 avg 와 분리)
        maxSpeedKmh = quarters.map(\.maxSpeedKmh).max() ?? 0
        sprintCount = quarters.reduce(0) { $0 + $1.sprintCount }
        let totalDuration = quarters.reduce(0) { $0 + $1.durationSeconds }
        if totalDuration > 0 {
            // duration 가중 평균 심박
            let weighted = quarters.reduce(0.0) { $0 + Double($1.avgHeartRate) * Double($1.durationSeconds) }
            avgHeartRate = Int((weighted / Double(totalDuration)).rounded())
        } else {
            avgHeartRate = 0
        }
    }
}
