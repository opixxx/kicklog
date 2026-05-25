#if DEBUG
import Foundation
import SwiftData

// 시뮬레이터/개발 빌드에서만 동작 — SwiftData 빈 상태일 때 샘플 Match + QuarterWorkout 주입.
// 실제 HealthKit raw 가 시뮬레이터에 없으므로 Phase E 검증용.
@MainActor
enum SampleDataSeeder {
    static func seedIfNeeded(_ context: ModelContext) {
        let existing = (try? context.fetch(FetchDescriptor<Match>()))?.count ?? 0
        guard existing == 0 else { return }
        seed(into: context)
    }

    private static func seed(into context: ModelContext) {
        let calendar = Calendar(identifier: .gregorian)
        let now = Date()

        let scenarios: [(daysAgo: Int, opponent: String, result: String, goals: Int, distance: Int, maxSpeed: Double, sprint: Int, hr: Int)] = [
            (7, "FC블루스", "W", 2, 3200, 19.4, 14, 158),
            (14, "레전드FC", "D", 1, 2800, 17.1, 9, 162),
            (21, "어반FC", "L", 0, 3400, 18.0, 11, 168),
            (28, "옆동네FC", "W", 1, 3000, 18.6, 12, 156),
            (35, "한강조축", "W", 3, 3700, 20.2, 16, 161),
        ]

        for scenario in scenarios {
            guard let playedAt = calendar.date(byAdding: .day, value: -scenario.daysAgo, to: now) else { continue }

            let match = Match(
                playedAt: playedAt,
                opponentName: scenario.opponent,
                result: scenario.result,
                position: "MF",
                userGoals: scenario.goals,
                userAssists: 1,
                totalDistanceM: scenario.distance,
                maxSpeedKmh: scenario.maxSpeed,
                sprintCount: scenario.sprint,
                avgHeartRate: scenario.hr,
                labeledAt: playedAt
            )
            context.insert(match)

            // 4쿼터 합성
            for q in 1...4 {
                let qStart = calendar.date(byAdding: .minute, value: (q - 1) * 30, to: playedAt) ?? playedAt
                let qEnd = calendar.date(byAdding: .minute, value: 25, to: qStart) ?? qStart
                let quarter = QuarterWorkout(
                    sourceWorkoutUUID: UUID().uuidString,
                    quarterNo: q,
                    startedAt: qStart,
                    endedAt: qEnd,
                    durationSeconds: 25 * 60,
                    distanceM: scenario.distance / 4,
                    avgSpeedKmh: scenario.maxSpeed * 0.85,
                    avgHeartRate: scenario.hr,
                    maxHeartRate: scenario.hr + 8,
                    sprintCount: scenario.sprint / 4,
                    activeEnergyKcal: 120
                )
                quarter.match = match
                context.insert(quarter)
            }
        }

        // 라벨링 대기 큐 2개 (labeledAt == nil)
        for daysAgo in [1, 4] {
            guard let detectedAt = calendar.date(byAdding: .day, value: -daysAgo, to: now) else { continue }
            let pending = Match(playedAt: detectedAt)
            context.insert(pending)
            for q in 1...4 {
                let qStart = calendar.date(byAdding: .minute, value: (q - 1) * 30, to: detectedAt) ?? detectedAt
                let qEnd = calendar.date(byAdding: .minute, value: 25, to: qStart) ?? qStart
                let quarter = QuarterWorkout(
                    sourceWorkoutUUID: UUID().uuidString,
                    quarterNo: 0,
                    startedAt: qStart,
                    endedAt: qEnd,
                    durationSeconds: 25 * 60,
                    distanceM: 800,
                    avgSpeedKmh: 16,
                    avgHeartRate: 155,
                    maxHeartRate: 165,
                    sprintCount: 3,
                    activeEnergyKcal: 110
                )
                quarter.match = pending
                context.insert(quarter)
            }
        }

        do { try context.save() } catch {
            print("SampleDataSeeder: save 실패 — \(error)")
        }
    }
}
#endif
