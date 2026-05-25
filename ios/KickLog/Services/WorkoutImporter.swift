import Foundation
import HealthKit
import SwiftData

// ADR-0004 D4 + D8 — 새 Soccer Workout 을 incremental fetch (HKAnchoredObjectQuery) 하고
// QuarterWorkout 으로 변환해 SwiftData 에 저장한다. anchor 는 HealthKitState 에 영속화.
@MainActor
final class WorkoutImporter {
    private let store: HKHealthStore
    private let modelContext: ModelContext
    private let analyzer: WorkoutAnalyzer
    private let grouper: WorkoutGrouper

    init(
        store: HKHealthStore,
        modelContext: ModelContext,
        analyzer: WorkoutAnalyzer? = nil,
        grouper: WorkoutGrouper? = nil
    ) {
        self.store = store
        self.modelContext = modelContext
        self.analyzer = analyzer ?? WorkoutAnalyzer()
        self.grouper = grouper ?? WorkoutGrouper(modelContext: modelContext, store: store)
    }

    // 새 Soccer 워크아웃을 페치 → 분석 → SwiftData 저장 → 자동 그룹핑.
    // anchor 기반 incremental — 이미 처리한 워크아웃은 다시 안 옴.
    func importNewSoccerWorkouts() async {
        let workoutType = HKObjectType.workoutType()
        let predicate = HKQuery.predicateForWorkouts(with: .soccer)
        let anchor = await loadAnchor()

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let query = HKAnchoredObjectQuery(
                type: workoutType,
                predicate: predicate,
                anchor: anchor,
                limit: HKObjectQueryNoLimit
            ) { [weak self] _, samples, _, newAnchor, error in
                if let error {
                    print("WorkoutImporter: HKAnchoredObjectQuery 실패 — \(error)")
                    continuation.resume()
                    return
                }
                let workouts = (samples as? [HKWorkout]) ?? []
                Task { @MainActor [weak self] in
                    if let newAnchor {
                        await self?.saveAnchor(newAnchor)
                    }
                    await self?.importAll(workouts: workouts)
                    continuation.resume()
                }
            }
            store.execute(query)
        }
    }

    private func importAll(workouts: [HKWorkout]) async {
        for workout in workouts {
            await importOne(workout)
        }
        do { try modelContext.save() } catch {
            print("WorkoutImporter: SwiftData 저장 실패 — \(error)")
        }
    }

    private func importOne(_ workout: HKWorkout) async {
        let uuidString = workout.uuid.uuidString

        // 중복 import 방지 (HKWorkout.uuid UNIQUE on QuarterWorkout)
        let descriptor = FetchDescriptor<QuarterWorkout>(
            predicate: #Predicate { $0.sourceWorkoutUUID == uuidString }
        )
        if (try? modelContext.fetch(descriptor))?.isEmpty == false { return }

        // raw → 집계 (Phase C)
        let metrics = await analyzer.analyze(workout: workout, store: store)

        let quarter = QuarterWorkout(
            sourceWorkoutUUID: uuidString,
            quarterNo: 0,                            // 라벨링 시점에 결정
            startedAt: workout.startDate,
            endedAt: workout.endDate,
            durationSeconds: Int(workout.duration),
            distanceM: metrics.distanceM,
            avgSpeedKmh: metrics.avgSpeedKmh,
            avgHeartRate: metrics.avgHeartRate,
            maxHeartRate: metrics.maxHeartRate,
            sprintCount: metrics.sprintCount,
            activeEnergyKcal: metrics.activeEnergyKcal,
            trimmed: false
        )
        modelContext.insert(quarter)

        // 자동 그룹핑 (Phase D)
        await grouper.assignToMatch(quarter)
    }

    // MARK: - anchor 영속화

    private static let anchorKey = "workoutAnchor"

    private func loadAnchor() async -> HKQueryAnchor? {
        let key = Self.anchorKey
        let descriptor = FetchDescriptor<HealthKitState>(
            predicate: #Predicate { $0.key == key }
        )
        guard let state = (try? modelContext.fetch(descriptor))?.first,
              let data = state.anchorData else { return nil }
        return try? NSKeyedUnarchiver.unarchivedObject(ofClass: HKQueryAnchor.self, from: data)
    }

    private func saveAnchor(_ anchor: HKQueryAnchor) async {
        guard let data = try? NSKeyedArchiver.archivedData(withRootObject: anchor, requiringSecureCoding: true) else {
            return
        }
        let key = Self.anchorKey
        let descriptor = FetchDescriptor<HealthKitState>(
            predicate: #Predicate { $0.key == key }
        )
        if let existing = (try? modelContext.fetch(descriptor))?.first {
            existing.anchorData = data
            existing.lastFetchedAt = .now
        } else {
            let state = HealthKitState(key: key, anchorData: data, lastFetchedAt: .now)
            modelContext.insert(state)
        }
    }
}
