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
    // 가입일 이전 워크아웃은 import 하지 않음 — 옛 백데이터로 라벨링 대기 큐가 오염되지 않도록.
    func importNewSoccerWorkouts() async {
        // User 가 SwiftData 에 아직 영속화되기 전이면 import 건너뜀 (가입일 기준 없음).
        guard let signupDate = currentUserSignupDate() else {
            print("WorkoutImporter: User 미존재 — import 건너뜀 (가입 완료 후 재호출)")
            return
        }

        // 이전 빌드에서 import 됐던 가입일 이전 미라벨 매치 일괄 정리 (idempotent).
        // 라벨링 완료한 매치는 사용자가 직접 결정 — 매치 상세 → 삭제 (DELETE /matches/{id}).
        cleanupPreSignupUnlabeledMatches(signupDate: signupDate)

        let workoutType = HKObjectType.workoutType()
        let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            HKQuery.predicateForWorkouts(with: .soccer),
            HKQuery.predicateForSamples(withStart: signupDate, end: nil, options: .strictStartDate),
        ])
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
                    self?.cleanupDuplicatesOfLabeledMatches()
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
        let lowerBound = workout.startDate.addingTimeInterval(-2)
        let upperBound = workout.startDate.addingTimeInterval(2)

        // 중복 import 방지: 같은 HealthKit UUID 거나, 같은 시작 시각(±2초)의 쿼터가 이미 있으면 skip.
        // 시각 매칭은 백엔드 복구분(UUID 형식 차이 등으로 UUID 매칭이 빗나가는 경우)까지 막는 안전망 —
        // 기기 재설치 후 복구↔재import 경쟁으로 같은 워크아웃이 중복 라벨링 큐로 뜨는 것을 방지한다.
        let descriptor = FetchDescriptor<QuarterWorkout>(
            predicate: #Predicate {
                $0.sourceWorkoutUUID == uuidString
                    || ($0.startedAt >= lowerBound && $0.startedAt <= upperBound)
            }
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
            maxSpeedKmh: metrics.maxSpeedKmh,
            avgHeartRate: metrics.avgHeartRate,
            maxHeartRate: metrics.maxHeartRate,
            sprintCount: metrics.sprintCount,
            activeEnergyKcal: metrics.activeEnergyKcal,
            trimmed: false,
            highIntensityRunCount: metrics.highIntensityRunCount,
            speedMetricsAvailable: metrics.speedMetricsAvailable,
            analysisVersion: WorkoutAnalyzer.currentAlgorithmVersion
        )
        modelContext.insert(quarter)

        // 자동 그룹핑 (Phase D)
        await grouper.assignToMatch(quarter)
    }

    // MARK: - 가입일 조회

    // SwiftData 에 영속화된 본인 User.createdAt 반환. 1단말 MVP 라 첫 행 신뢰.
    private func currentUserSignupDate() -> Date? {
        let descriptor = FetchDescriptor<User>()
        return (try? modelContext.fetch(descriptor))?.first?.createdAt
    }

    // MARK: - 가입일 이전 미라벨 매치 cleanup

    // 가입일 이전에 시작된 라벨링 안 한 매치를 일괄 삭제.
    // Match.quarters 는 @Relationship(deleteRule: .cascade) 라 연관 QuarterWorkout 도 자동 정리.
    // 라벨링 완료한 매치(labeledAt != nil)는 의도적 데이터라 그대로 둔다 — 사용자가 매치 상세에서
    // 직접 삭제 (DELETE /matches/{id} 백엔드 sync 포함) 여부를 결정.
    private func cleanupPreSignupUnlabeledMatches(signupDate: Date) {
        let descriptor = FetchDescriptor<Match>(
            predicate: #Predicate { $0.labeledAt == nil && $0.playedAt < signupDate }
        )
        guard let matches = try? modelContext.fetch(descriptor), !matches.isEmpty else { return }
        for match in matches {
            modelContext.delete(match)
        }
        modelContext.saveOrLog(caller: "WorkoutImporter.cleanupPreSignupUnlabeledMatches")
        print("WorkoutImporter: 가입일 이전 미라벨 매치 \(matches.count)건 정리")
    }

    // MARK: - 라벨링 경기와 중복된 미라벨 매치 cleanup

    // 라벨링된 경기와 중복되는 미라벨 매치를 제거한다. 두 경우를 정리한다:
    //  ① 라벨 경기와 같은 워크아웃(쿼터 시작 시각 일치)을 가진 미라벨 매치
    //  ② 쿼터가 라벨 경기로 흡수돼(sourceWorkoutUUID unique 충돌) 빈 껍데기로 남은 미라벨 매치
    // 기기 재설치 후 백엔드 상세 복구와 HealthKit 재import 가 같은 워크아웃을 가리킬 때 발생하는
    // 중복/잔재를 청소 (idempotent — 매 import 후 1회). 라벨링 완료분은 손대지 않는다.
    private func cleanupDuplicatesOfLabeledMatches() {
        let labeledDescriptor = FetchDescriptor<Match>(
            predicate: #Predicate { $0.labeledAt != nil }
        )
        guard let labeled = try? modelContext.fetch(labeledDescriptor) else { return }
        // 라벨링 경기들의 쿼터 시작 시각(초 단위 반올림)을 집합으로 — 직렬화 ±1초 오차 흡수.
        let labeledStartSeconds = Set(
            labeled.flatMap { $0.quarters.map { Int($0.startedAt.timeIntervalSince1970.rounded()) } }
        )
        guard !labeledStartSeconds.isEmpty else { return }

        let unlabeledDescriptor = FetchDescriptor<Match>(
            predicate: #Predicate { $0.labeledAt == nil }
        )
        guard let unlabeled = try? modelContext.fetch(unlabeledDescriptor) else { return }

        var removed = 0
        for match in unlabeled {
            // ② 쿼터가 라벨 경기로 흡수돼 비어버린 미라벨(빈 껍데기)
            let isEmpty = match.quarters.isEmpty
            // ① 라벨 경기와 시작 시각이 겹치는 미라벨
            let isDuplicate = match.quarters.contains {
                labeledStartSeconds.contains(Int($0.startedAt.timeIntervalSince1970.rounded()))
            }
            if isEmpty || isDuplicate {
                modelContext.delete(match)
                removed += 1
            }
        }
        if removed > 0 {
            modelContext.saveOrLog(caller: "WorkoutImporter.cleanupDuplicatesOfLabeledMatches")
            print("WorkoutImporter: 라벨링 경기와 중복된 미라벨 매치 \(removed)건 정리")
        }
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
