import Foundation
import SwiftData

// ADR-0004 D2 — SwiftData @Model 정의.
// 본인(편집 가능): User, Match, QuarterWorkout, Venue, FriendInvitation
// 친구(read-only 캐시): Friend, FriendMatch, FriendQuarterWorkout
// HealthKit state (Observer anchor 영속화): HealthKitState

// MARK: - 본인 도메인

@Model
final class User {
    @Attribute(.unique) var serverId: Int64
    var displayName: String
    var email: String?
    var hideHeartRate: Bool
    var createdAt: Date
    var lastSyncedAt: Date?

    init(
        serverId: Int64,
        displayName: String,
        email: String? = nil,
        hideHeartRate: Bool = false,
        createdAt: Date = .now,
        lastSyncedAt: Date? = nil
    ) {
        self.serverId = serverId
        self.displayName = displayName
        self.email = email
        self.hideHeartRate = hideHeartRate
        self.createdAt = createdAt
        self.lastSyncedAt = lastSyncedAt
    }
}

extension User {
    // 서버 UserDTO → SwiftData @Model UPSERT. AuthService 로그인 + UserService.fetchMe 공통 경로.
    @MainActor
    static func upsert(from dto: UserDTO, into context: ModelContext) -> User {
        let serverId = dto.id
        let descriptor = FetchDescriptor<User>(
            predicate: #Predicate { $0.serverId == serverId }
        )
        if let existing = try? context.fetch(descriptor).first {
            existing.displayName = dto.displayName
            existing.email = dto.email
            existing.hideHeartRate = dto.hideHeartRate
            existing.createdAt = dto.createdAt
            existing.lastSyncedAt = .now
            try? context.save()
            return existing
        }
        let user = User(
            serverId: dto.id,
            displayName: dto.displayName,
            email: dto.email,
            hideHeartRate: dto.hideHeartRate,
            createdAt: dto.createdAt,
            lastSyncedAt: .now
        )
        context.insert(user)
        try? context.save()
        return user
    }
}

@Model
final class Match {
    @Attribute(.unique) var clientMatchId: UUID
    var serverId: Int64?
    var playedAt: Date
    var venueId: Int64?
    var venueName: String?     // FriendMatch.venueName 패턴 — 백엔드 join 캐시
    var opponentName: String?
    var result: String?        // "W" | "D" | "L"
    var position: String?      // "GK" | "DF" | "MF" | "FW"
    var userGoals: Int?
    var userAssists: Int?
    var opponentGoals: Int?       // 상대팀 골 (V9 백엔드 동기화). null = 미입력.
    var teamGoals: Int?           // 팀 전체 골 (V10 백엔드). result 는 teamGoals vs opponentGoals 로 백엔드 자동 derive.

    // ADR-0004 D8 헤드라인 4지표 (집계 캐시)
    var totalDistanceM: Int
    var maxSpeedKmh: Double
    var sprintCount: Int
    var avgHeartRate: Int

    // 동기화 상태
    var labeledAt: Date?
    var syncedAt: Date?
    var lastSyncAttemptAt: Date?
    var syncErrorMessage: String?

    @Relationship(deleteRule: .cascade, inverse: \QuarterWorkout.match)
    var quarters: [QuarterWorkout]

    init(
        clientMatchId: UUID = UUID(),
        playedAt: Date,
        venueId: Int64? = nil,
        venueName: String? = nil,
        opponentName: String? = nil,
        result: String? = nil,
        position: String? = nil,
        userGoals: Int? = nil,
        userAssists: Int? = nil,
        opponentGoals: Int? = nil,
        teamGoals: Int? = nil,
        totalDistanceM: Int = 0,
        maxSpeedKmh: Double = 0,
        sprintCount: Int = 0,
        avgHeartRate: Int = 0,
        labeledAt: Date? = nil
    ) {
        self.clientMatchId = clientMatchId
        self.playedAt = playedAt
        self.venueId = venueId
        self.venueName = venueName
        self.opponentName = opponentName
        self.result = result
        self.position = position
        self.userGoals = userGoals
        self.userAssists = userAssists
        self.opponentGoals = opponentGoals
        self.teamGoals = teamGoals
        self.totalDistanceM = totalDistanceM
        self.maxSpeedKmh = maxSpeedKmh
        self.sprintCount = sprintCount
        self.avgHeartRate = avgHeartRate
        self.labeledAt = labeledAt
        self.quarters = []
    }
}

@Model
final class QuarterWorkout {
    @Attribute(.unique) var sourceWorkoutUUID: String   // HKWorkout.uuid
    var quarterNo: Int                                   // 1~4, 미라벨링 시 0
    var startedAt: Date
    var endedAt: Date
    var durationSeconds: Int

    // 쿼터별 집계 (ADR-0004 D8 캐시)
    var distanceM: Int
    var avgSpeedKmh: Double
    var avgHeartRate: Int
    var maxHeartRate: Int
    var sprintCount: Int
    var activeEnergyKcal: Int
    var trimmed: Bool

    var match: Match?

    init(
        sourceWorkoutUUID: String,
        quarterNo: Int = 0,
        startedAt: Date,
        endedAt: Date,
        durationSeconds: Int,
        distanceM: Int = 0,
        avgSpeedKmh: Double = 0,
        avgHeartRate: Int = 0,
        maxHeartRate: Int = 0,
        sprintCount: Int = 0,
        activeEnergyKcal: Int = 0,
        trimmed: Bool = false,
        match: Match? = nil
    ) {
        self.sourceWorkoutUUID = sourceWorkoutUUID
        self.quarterNo = quarterNo
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.durationSeconds = durationSeconds
        self.distanceM = distanceM
        self.avgSpeedKmh = avgSpeedKmh
        self.avgHeartRate = avgHeartRate
        self.maxHeartRate = maxHeartRate
        self.sprintCount = sprintCount
        self.activeEnergyKcal = activeEnergyKcal
        self.trimmed = trimmed
        self.match = match
    }
}

@Model
final class Venue {
    @Attribute(.unique) var serverId: Int64
    var name: String
    var geoLat: Double
    var geoLng: Double
    var createdAt: Date

    init(serverId: Int64, name: String, geoLat: Double, geoLng: Double, createdAt: Date = .now) {
        self.serverId = serverId
        self.name = name
        self.geoLat = geoLat
        self.geoLng = geoLng
        self.createdAt = createdAt
    }
}

extension Venue {
    // 서버 VenueResponse → SwiftData @Model UPSERT.
    @MainActor
    static func upsert(from dto: VenueResponse, into context: ModelContext) -> Venue {
        let serverId = dto.id
        let descriptor = FetchDescriptor<Venue>(
            predicate: #Predicate { $0.serverId == serverId }
        )
        if let existing = try? context.fetch(descriptor).first {
            existing.name = dto.name
            existing.geoLat = dto.geoLat
            existing.geoLng = dto.geoLng
            existing.createdAt = dto.createdAt
            try? context.save()
            return existing
        }

        let venue = Venue(
            serverId: dto.id,
            name: dto.name,
            geoLat: dto.geoLat,
            geoLng: dto.geoLng,
            createdAt: dto.createdAt
        )
        context.insert(venue)
        try? context.save()
        return venue
    }
}

// MARK: - 친구 (read-only 캐시)

@Model
final class Friend {
    @Attribute(.unique) var friendUserId: Int64
    var displayName: String
    var friendshipStatus: String    // "pending" | "accepted"
    var initiatedByMe: Bool
    var hideHeartRate: Bool         // 친구가 hide 시 본인이 마스킹
    var lastFetchedAt: Date?

    init(
        friendUserId: Int64,
        displayName: String,
        friendshipStatus: String,
        initiatedByMe: Bool,
        hideHeartRate: Bool = false,
        lastFetchedAt: Date? = nil
    ) {
        self.friendUserId = friendUserId
        self.displayName = displayName
        self.friendshipStatus = friendshipStatus
        self.initiatedByMe = initiatedByMe
        self.hideHeartRate = hideHeartRate
        self.lastFetchedAt = lastFetchedAt
    }
}

@Model
final class FriendMatch {
    @Attribute(.unique) var serverId: Int64
    var friendUserId: Int64
    var playedAt: Date
    var venueName: String?
    var opponentName: String?
    var result: String?
    var position: String?
    var userGoals: Int?
    var userAssists: Int?

    var totalDistanceM: Int
    var maxSpeedKmh: Double
    var sprintCount: Int
    var avgHeartRate: Int?           // hide 시 nil

    var cachedAt: Date

    @Relationship(deleteRule: .cascade, inverse: \FriendQuarterWorkout.friendMatch)
    var quarters: [FriendQuarterWorkout]

    init(
        serverId: Int64,
        friendUserId: Int64,
        playedAt: Date,
        venueName: String? = nil,
        opponentName: String? = nil,
        result: String? = nil,
        position: String? = nil,
        userGoals: Int? = nil,
        userAssists: Int? = nil,
        totalDistanceM: Int = 0,
        maxSpeedKmh: Double = 0,
        sprintCount: Int = 0,
        avgHeartRate: Int? = nil,
        cachedAt: Date = .now
    ) {
        self.serverId = serverId
        self.friendUserId = friendUserId
        self.playedAt = playedAt
        self.venueName = venueName
        self.opponentName = opponentName
        self.result = result
        self.position = position
        self.userGoals = userGoals
        self.userAssists = userAssists
        self.totalDistanceM = totalDistanceM
        self.maxSpeedKmh = maxSpeedKmh
        self.sprintCount = sprintCount
        self.avgHeartRate = avgHeartRate
        self.cachedAt = cachedAt
        self.quarters = []
    }
}

@Model
final class FriendQuarterWorkout {
    @Attribute(.unique) var serverId: Int64
    var quarterNo: Int
    var distanceM: Int
    var avgSpeedKmh: Double
    var avgHeartRate: Int?           // hide 시 nil
    var sprintCount: Int

    var friendMatch: FriendMatch?

    init(
        serverId: Int64,
        quarterNo: Int,
        distanceM: Int,
        avgSpeedKmh: Double,
        avgHeartRate: Int? = nil,
        sprintCount: Int,
        friendMatch: FriendMatch? = nil
    ) {
        self.serverId = serverId
        self.quarterNo = quarterNo
        self.distanceM = distanceM
        self.avgSpeedKmh = avgSpeedKmh
        self.avgHeartRate = avgHeartRate
        self.sprintCount = sprintCount
        self.friendMatch = friendMatch
    }
}

@Model
final class FriendInvitation {
    @Attribute(.unique) var token: String
    var expiresAt: Date
    var useCount: Int
    var createdAt: Date

    init(token: String, expiresAt: Date, useCount: Int = 0, createdAt: Date = .now) {
        self.token = token
        self.expiresAt = expiresAt
        self.useCount = useCount
        self.createdAt = createdAt
    }
}

// MARK: - HealthKit anchor 영속화 (ADR-0004 D4)

@Model
final class HealthKitState {
    @Attribute(.unique) var key: String       // "workoutAnchor"
    var anchorData: Data?
    var lastFetchedAt: Date?

    init(key: String, anchorData: Data? = nil, lastFetchedAt: Date? = nil) {
        self.key = key
        self.anchorData = anchorData
        self.lastFetchedAt = lastFetchedAt
    }
}

// MARK: - 공통 protocol (SwiftUI 컴포넌트 재사용)

protocol MatchDisplayable {
    var playedAt: Date { get }
    var venueDisplayName: String? { get }
    var opponentName: String? { get }
    var result: String? { get }
    var totalDistanceM: Int { get }
    var maxSpeedKmh: Double { get }
    var sprintCount: Int { get }
    var displayedAvgHeartRate: Int? { get }   // 친구가 hide 시 nil
}

extension Match: MatchDisplayable {
    var venueDisplayName: String? { venueName }
    var displayedAvgHeartRate: Int? { avgHeartRate }
}

extension FriendMatch: MatchDisplayable {
    var venueDisplayName: String? { venueName }
    var displayedAvgHeartRate: Int? { avgHeartRate }
}

// MARK: - 모든 모델 타입 — ModelContainer 등록용

enum KickLogSchema {
    static let allModels: [any PersistentModel.Type] = [
        User.self,
        Match.self,
        QuarterWorkout.self,
        Venue.self,
        Friend.self,
        FriendMatch.self,
        FriendQuarterWorkout.self,
        FriendInvitation.self,
        HealthKitState.self,
    ]
}
