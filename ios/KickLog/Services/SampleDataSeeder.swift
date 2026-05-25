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

        // Venue 4개 시드 — geo 는 더미 좌표
        let venueSeeds: [(serverId: Int64, name: String, lat: Double, lng: Double)] = [
            (1, "마포 풋살장", 37.547, 126.910),
            (2, "양화 한강", 37.547, 126.901),
            (3, "○○공원 운동장", 37.560, 126.930),
            (4, "성수 스카이파크", 37.544, 127.057),
        ]
        var venuesById: [Int64: Venue] = [:]
        for v in venueSeeds {
            let venue = Venue(serverId: v.serverId, name: v.name, geoLat: v.lat, geoLng: v.lng)
            context.insert(venue)
            venuesById[v.serverId] = venue
        }

        let scenarios: [(daysAgo: Int, opponent: String, venueId: Int64, result: String, userGoals: Int, opponentGoals: Int, distance: Int, maxSpeed: Double, sprint: Int, hr: Int)] = [
            (7, "FC블루스", 1, "W", 4, 2, 3200, 19.4, 14, 158),
            (14, "레전드FC", 2, "D", 2, 2, 2800, 17.1, 9, 162),
            (21, "어반FC", 1, "L", 1, 3, 3400, 18.0, 11, 168),
            (28, "옆동네FC", 3, "W", 3, 1, 3000, 18.6, 12, 156),
            (35, "한강조축", 2, "W", 5, 3, 3700, 20.2, 16, 161),
        ]

        for scenario in scenarios {
            guard let playedAt = calendar.date(byAdding: .day, value: -scenario.daysAgo, to: now) else { continue }

            let venue = venuesById[scenario.venueId]
            let match = Match(
                playedAt: playedAt,
                venueId: scenario.venueId,
                venueName: venue?.name,
                opponentName: scenario.opponent,
                result: scenario.result,
                position: "MF",
                userGoals: scenario.userGoals,
                userAssists: 1,
                opponentGoals: scenario.opponentGoals,
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
        // 첫 번째: Q2 가 32분 (30분 초과 워닝 케이스 — Trim sheet 테스트용)
        for daysAgo in [1, 4] {
            guard let detectedAt = calendar.date(byAdding: .day, value: -daysAgo, to: now) else { continue }
            let pending = Match(playedAt: detectedAt)
            context.insert(pending)
            for q in 1...4 {
                let qStart = calendar.date(byAdding: .minute, value: (q - 1) * 30, to: detectedAt) ?? detectedAt
                // daysAgo == 1 이고 q == 2 면 32분 (overtime), 나머지 25분
                let durationMinutes = (daysAgo == 1 && q == 2) ? 32 : 25
                let qEnd = calendar.date(byAdding: .minute, value: durationMinutes, to: qStart) ?? qStart
                let quarter = QuarterWorkout(
                    sourceWorkoutUUID: UUID().uuidString,
                    quarterNo: 0,
                    startedAt: qStart,
                    endedAt: qEnd,
                    durationSeconds: durationMinutes * 60,
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
