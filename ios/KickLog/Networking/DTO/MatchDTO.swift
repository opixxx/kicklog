import Foundation
import SwiftData

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
    let opponentGoals: Int?       // null = 미입력, 0 = 명시적 무실점 (api-spec §5.1)
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

struct MatchListResponse: Decodable {
    let content: [MatchSummaryResponse]
    let size: Int
    let nextCursor: String?
    let hasNext: Bool
}

struct MatchSummaryResponse: Decodable {
    let id: Int64
    let clientMatchId: UUID
    let venueId: Int64?
    let playedAt: Date
    let opponent: String?
    let result: String?
    let position: String?
    let goals: Int
    let assists: Int
    let opponentGoals: Int?
    let totalDistanceM: Int
    let maxSpeedKmh: Double
    let sprintCount: Int
    let avgHeartRate: Int?
    let quarterCount: Int
}

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
    let opponentGoals: Int?
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

// MARK: - 목록 응답 (5.2 본인, 5.5 친구 공용)

struct MatchSummaryResponse: Decodable, Hashable {
    let id: Int64
    let clientMatchId: UUID
    let venueId: Int64?
    let playedAt: Date
    let opponent: String?
    let result: String?           // "WIN" | "DRAW" | "LOSS" | null
    let position: String?         // "GK" | "DF" | "MF" | "FW" | null
    let goals: Int
    let assists: Int
    let opponentGoals: Int?
    let totalDistanceM: Int
    let maxSpeedKmh: Double
    let sprintCount: Int
    let avgHeartRate: Int?        // 친구 hideHeartRate=true 면 null
    let quarterCount: Int
}

struct CursorMatchResponse: Decodable {
    let content: [MatchSummaryResponse]
    let size: Int
    let nextCursor: String?
    let hasNext: Bool
}

// MARK: - 표시 변환 — MatchSummaryResponse → MatchRowData

extension MatchSummaryResponse {
    var rowData: MatchRowData {
        MatchRowData(
            dateNum: Self.dateNumFormatter.string(from: playedAt),
            dow: Self.dowFormatter.string(from: playedAt),
            opponent: opponent ?? "—",
            venue: "—",                               // 친구 경기는 venue 이름이 응답에 없음 (venueId 만 노출)
            result: MatchResult.from(Self.resultToCode(result)),
            score: Match.formatScore(userGoals: goals, opponentGoals: opponentGoals),
            distanceKm: Double(totalDistanceM) / 1000.0,
            avgSpeedKmh: maxSpeedKmh,
            sprintCount: sprintCount,
            avgHeartRateBpm: avgHeartRate ?? 0        // null = 비공개 → 행에서는 0 으로 표시
        )
    }

    // "WIN"/"DRAW"/"LOSS" → "W"/"D"/"L" (MatchResult.from 입력 형식)
    private static func resultToCode(_ wire: String?) -> String? {
        switch wire {
        case "WIN": return "W"
        case "DRAW": return "D"
        case "LOSS": return "L"
        default: return nil
        }
    }

    private static let dateNumFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "M/d"
        return f
    }()

    private static let dowFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ko_KR")
        f.dateFormat = "E"
        return f
    }()
}

// MARK: - SwiftData Match → PutMatchRequest

extension Match {
    // PutMatchRequest 변환. venueId 가 nil 또는 음수(로컬 임시) 면 nil 반환 — 동기화 skip.
    // result 는 "W"/"D"/"L" → "WIN"/"DRAW"/"LOSS" 변환 (api-spec 형식).
    // opponentGoals 는 backend V9 (PR #26) 이후 정상 sync.
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
            opponentGoals: opponentGoals,
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

// MARK: - Response DTO → SwiftData Match

extension Match {
    @discardableResult
    @MainActor
    static func upsertSummary(from dto: MatchSummaryResponse, into context: ModelContext) -> Match {
        let match: Match
        if let existing = find(serverId: dto.id, clientMatchId: dto.clientMatchId, in: context) {
            match = existing
        } else {
            match = Match(playedAt: dto.playedAt)
            context.insert(match)
        }
        match.applySummary(dto, in: context)
        try? context.save()
        return match
    }

    @discardableResult
    @MainActor
    static func upsertDetail(from dto: MatchDetailResponse, into context: ModelContext) -> Match {
        let match: Match
        if let existing = find(serverId: dto.id, clientMatchId: dto.clientMatchId, in: context) {
            match = existing
        } else {
            match = Match(playedAt: dto.playedAt)
            context.insert(match)
        }
        match.applyDetail(dto, in: context)
        try? context.save()
        return match
    }

    @MainActor
    private static func find(serverId: Int64, clientMatchId: UUID, in context: ModelContext) -> Match? {
        let byClientId = FetchDescriptor<Match>(
            predicate: #Predicate { $0.clientMatchId == clientMatchId }
        )
        if let match = try? context.fetch(byClientId).first {
            return match
        }

        let byServerId = FetchDescriptor<Match>(
            predicate: #Predicate { $0.serverId == serverId }
        )
        return try? context.fetch(byServerId).first
    }

    @MainActor
    private func applySummary(_ dto: MatchSummaryResponse, in context: ModelContext) {
        applyCommon(
            serverId: dto.id,
            clientMatchId: dto.clientMatchId,
            venueId: dto.venueId,
            playedAt: dto.playedAt,
            opponent: dto.opponent,
            result: dto.result,
            position: dto.position,
            goals: dto.goals,
            assists: dto.assists,
            opponentGoals: dto.opponentGoals,
            totalDistanceM: dto.totalDistanceM,
            maxSpeedKmh: dto.maxSpeedKmh,
            sprintCount: dto.sprintCount,
            avgHeartRate: dto.avgHeartRate,
            in: context
        )
    }

    @MainActor
    private func applyDetail(_ dto: MatchDetailResponse, in context: ModelContext) {
        applyCommon(
            serverId: dto.id,
            clientMatchId: dto.clientMatchId,
            venueId: dto.venueId,
            playedAt: dto.playedAt,
            opponent: dto.opponent,
            result: dto.result,
            position: dto.position,
            goals: dto.goals,
            assists: dto.assists,
            opponentGoals: dto.opponentGoals,
            totalDistanceM: dto.totalDistanceM,
            maxSpeedKmh: dto.maxSpeedKmh,
            sprintCount: dto.sprintCount,
            avgHeartRate: dto.avgHeartRate,
            in: context
        )
        replaceQuarters(with: dto.quarters, in: context)
    }

    @MainActor
    private func applyCommon(
        serverId: Int64,
        clientMatchId: UUID,
        venueId: Int64?,
        playedAt: Date,
        opponent: String?,
        result: String?,
        position: String?,
        goals: Int,
        assists: Int,
        opponentGoals: Int?,
        totalDistanceM: Int,
        maxSpeedKmh: Double,
        sprintCount: Int,
        avgHeartRate: Int?,
        in context: ModelContext
    ) {
        self.serverId = serverId
        self.clientMatchId = clientMatchId
        self.venueId = venueId
        self.venueName = venueName(for: venueId, in: context) ?? self.venueName
        self.playedAt = playedAt
        opponentName = opponent
        self.result = Self.resultFromWire(result)
        self.position = position
        userGoals = goals
        userAssists = assists
        self.opponentGoals = opponentGoals
        self.totalDistanceM = totalDistanceM
        self.maxSpeedKmh = maxSpeedKmh
        self.sprintCount = sprintCount
        self.avgHeartRate = avgHeartRate ?? 0
        labeledAt = labeledAt ?? playedAt
        syncedAt = .now
        lastSyncAttemptAt = .now
        syncErrorMessage = nil
    }

    @MainActor
    private func replaceQuarters(with dtos: [QuarterDetailResponse], in context: ModelContext) {
        for quarter in quarters {
            context.delete(quarter)
        }
        quarters = dtos
            .sorted { $0.quarterNumber < $1.quarterNumber }
            .map { dto in
                QuarterWorkout(
                    sourceWorkoutUUID: dto.healthKitWorkoutId ?? "server-\(serverId ?? 0)-q\(dto.quarterNumber)",
                    quarterNo: dto.quarterNumber,
                    startedAt: dto.startedAt,
                    endedAt: dto.endedAt,
                    durationSeconds: dto.durationSeconds,
                    distanceM: dto.distanceM,
                    avgSpeedKmh: dto.avgSpeedKmh,
                    avgHeartRate: dto.avgHeartRate ?? 0,
                    maxHeartRate: dto.maxHeartRate ?? 0,
                    sprintCount: dto.sprintCount,
                    activeEnergyKcal: dto.activeEnergyKcal,
                    trimmed: true,
                    match: self
                )
            }
    }

    @MainActor
    private func venueName(for venueId: Int64?, in context: ModelContext) -> String? {
        guard let venueId else { return nil }
        let descriptor = FetchDescriptor<Venue>(
            predicate: #Predicate { $0.serverId == venueId }
        )
        return (try? context.fetch(descriptor).first)?.name
    }

    private static func resultFromWire(_ code: String?) -> String? {
        switch code {
        case "WIN": return "W"
        case "DRAW": return "D"
        case "LOSS": return "L"
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
