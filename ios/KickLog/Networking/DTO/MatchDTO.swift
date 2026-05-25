import Foundation

// api-spec.md §5 Matches — Request/Response DTO.

// MARK: - Request

struct PutMatchRequest: Encodable {
    let venueId: Int64
    let playedAt: Date
    let opponent: String?
    let result: String?           // "WIN" | "DRAW" | "LOSS"
    let position: String?         // "GK" | "DF" | "MF" | "FW"
    let goals: Int
    let assists: Int
    let totalDistanceM: Int
    let maxSpeedKmh: Double
    let sprintCount: Int
    let avgHeartRate: Int
    let quarters: [PutQuarterRequest]
}

struct PutQuarterRequest: Encodable {
    let quarterNumber: Int
    let healthKitWorkoutId: String
    let startedAt: Date
    let endedAt: Date
    let durationSeconds: Int
    let distanceM: Int
    let avgSpeedKmh: Double
    let avgHeartRate: Int
    let maxHeartRate: Int
    let sprintCount: Int
    let activeEnergyKcal: Int
}

// MARK: - Response

struct MatchDetailResponse: Decodable {
    let id: Int64
    let clientMatchId: UUID
    let venueId: Int64?
    let playedAt: Date
    let opponent: String?
    let result: String?
    let position: String?
    let goals: Int
    let assists: Int
    let totalDistanceM: Int
    let maxSpeedKmh: Double
    let sprintCount: Int
    let avgHeartRate: Int?
    let quarters: [QuarterDetailResponse]
}

struct QuarterDetailResponse: Decodable {
    let quarterNumber: Int
    let healthKitWorkoutId: String?
    let startedAt: Date
    let endedAt: Date
    let durationSeconds: Int
    let distanceM: Int
    let avgSpeedKmh: Double
    let avgHeartRate: Int?
    let maxHeartRate: Int?
    let sprintCount: Int
    let activeEnergyKcal: Int
}

// MARK: - SwiftData Match → PutMatchRequest

extension Match {
    // PutMatchRequest 변환. venueId 가 nil 또는 음수(로컬 임시) 면 nil 반환 — 동기화 skip.
    // result 는 "W"/"D"/"L" → "WIN"/"DRAW"/"LOSS" 변환 (api-spec 형식).
    // opponentGoals 는 backend schema 에 없어 미전송 (PR #15 후속 ADR-0003 보강 필요).
    func toPutRequest() -> PutMatchRequest? {
        guard let venueId, venueId > 0 else { return nil }
        let sortedQuarters = quarters
            .filter { $0.quarterNo > 0 }
            .sorted { $0.quarterNo < $1.quarterNo }
        guard !sortedQuarters.isEmpty else { return nil }

        return PutMatchRequest(
            venueId: venueId,
            playedAt: playedAt,
            opponent: opponentName,
            result: Self.resultToWire(result),
            position: position,
            goals: userGoals ?? 0,
            assists: userAssists ?? 0,
            totalDistanceM: totalDistanceM,
            maxSpeedKmh: maxSpeedKmh,
            sprintCount: sprintCount,
            avgHeartRate: avgHeartRate,
            quarters: sortedQuarters.map { $0.toPutRequest() }
        )
    }

    // "W"/"D"/"L" → "WIN"/"DRAW"/"LOSS"
    private static func resultToWire(_ code: String?) -> String? {
        switch code {
        case "W": return "WIN"
        case "D": return "DRAW"
        case "L": return "LOSS"
        default: return nil
        }
    }
}

extension QuarterWorkout {
    func toPutRequest() -> PutQuarterRequest {
        PutQuarterRequest(
            quarterNumber: quarterNo,
            healthKitWorkoutId: sourceWorkoutUUID,
            startedAt: startedAt,
            endedAt: endedAt,
            durationSeconds: durationSeconds,
            distanceM: distanceM,
            avgSpeedKmh: avgSpeedKmh,
            avgHeartRate: avgHeartRate,
            maxHeartRate: maxHeartRate,
            sprintCount: sprintCount,
            activeEnergyKcal: activeEnergyKcal
        )
    }
}
