import Foundation
import SwiftData

// ADR-0004 D2 — SwiftData @Model 정의.
// 본인(편집 가능): User, Match, QuarterWorkout, Venue
// 친구(read-only 캐시): Friend, FriendMatch, FriendQuarterWorkout
// HealthKit state (Observer anchor 영속화): HealthKitState

// MARK: - 본인 도메인

@Model
final class User {
    @Attribute(.unique) var serverId: Int64
    var displayName: String
    var email: String?
    var createdAt: Date
    var lastSyncedAt: Date?

    init(
        serverId: Int64,
        displayName: String,
        email: String? = nil,
        createdAt: Date = .now,
        lastSyncedAt: Date? = nil
    ) {
        self.serverId = serverId
        self.displayName = displayName
        self.email = email
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
            existing.createdAt = dto.createdAt
            existing.lastSyncedAt = .now
            context.saveOrLog(caller: "User.upsert")
            return existing
        }
        let user = User(
            serverId: dto.id,
            displayName: dto.displayName,
            email: dto.email,
            createdAt: dto.createdAt,
            lastSyncedAt: .now
        )
        context.insert(user)
        context.saveOrLog(caller: "User.upsert")
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

    // ADR-0012 — 고강도 러닝(기존 14km/h 지표 rename) + 속도 지표 신뢰 가능 여부.
    // speedMetricsAvailable=false (전 쿼터 저밀도) 면 최고속도·스프린트·고강도 러닝을 UI 에서 숨긴다.
    // 인라인 기본값 = SwiftData lightweight 마이그레이션의 기존 행 기본값.
    var highIntensityRunCount: Int = 0
    var speedMetricsAvailable: Bool = true

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
    var maxSpeedKmh: Double
    var avgHeartRate: Int
    var maxHeartRate: Int
    var sprintCount: Int
    var activeEnergyKcal: Int
    var trimmed: Bool

    // ADR-0012 — 고강도 러닝 + 속도 지표 신뢰 가능 여부(저밀도 데이터면 false).
    // analysisVersion: 지표 알고리즘 버전 (ADR-0004 D8 의 (C) Hybrid 진화).
    // 기존 행 기본값 1 = 구버전 산출물 → 앱 구동 시 일괄 재분석 대상.
    var highIntensityRunCount: Int = 0
    var speedMetricsAvailable: Bool = true
    var analysisVersion: Int = 1

    var match: Match?

    init(
        sourceWorkoutUUID: String,
        quarterNo: Int = 0,
        startedAt: Date,
        endedAt: Date,
        durationSeconds: Int,
        distanceM: Int = 0,
        avgSpeedKmh: Double = 0,
        maxSpeedKmh: Double = 0,
        avgHeartRate: Int = 0,
        maxHeartRate: Int = 0,
        sprintCount: Int = 0,
        activeEnergyKcal: Int = 0,
        trimmed: Bool = false,
        highIntensityRunCount: Int = 0,
        speedMetricsAvailable: Bool = true,
        analysisVersion: Int = 1,
        match: Match? = nil
    ) {
        self.sourceWorkoutUUID = sourceWorkoutUUID
        self.quarterNo = quarterNo
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.durationSeconds = durationSeconds
        self.distanceM = distanceM
        self.avgSpeedKmh = avgSpeedKmh
        self.maxSpeedKmh = maxSpeedKmh
        self.avgHeartRate = avgHeartRate
        self.maxHeartRate = maxHeartRate
        self.sprintCount = sprintCount
        self.activeEnergyKcal = activeEnergyKcal
        self.trimmed = trimmed
        self.highIntensityRunCount = highIntensityRunCount
        self.speedMetricsAvailable = speedMetricsAvailable
        self.analysisVersion = analysisVersion
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
            context.saveOrLog(caller: "Venue.upsert")
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
        context.saveOrLog(caller: "Venue.upsert")
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
    var lastFetchedAt: Date?

    init(
        friendUserId: Int64,
        displayName: String,
        friendshipStatus: String,
        initiatedByMe: Bool,
        lastFetchedAt: Date? = nil
    ) {
        self.friendUserId = friendUserId
        self.displayName = displayName
        self.friendshipStatus = friendshipStatus
        self.initiatedByMe = initiatedByMe
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

// MARK: - 경기 표시 변환 SoT (화면 간 중복 제거)

// 포지션·운동시간 등 순수 표시 변환. MatchDetailScreen / FriendMatchDetailScreen 양쪽에서 호출.
enum MatchFormat {
    // 포지션 코드 → 한글 풀네임. "GK" → "골키퍼 (GK)".
    static func positionLong(_ code: String?) -> String {
        switch code {
        case "GK": return "골키퍼 (GK)"
        case "DF": return "수비수 (DF)"
        case "MF": return "미드필더 (MF)"
        case "FW": return "공격수 (FW)"
        default: return "—"
        }
    }

    // 초 → "M:SS" 운동시간 라벨.
    static func durationLabel(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

// MARK: - VersionedSchema (ADR-0004 — 스키마 진화 대비)

// 현재 스키마 V1. 기본값 있는 필드 "추가"는 lightweight 마이그레이션 대상이라 SwiftData 가
// 자동 처리한다 (2026-07 ADR-0012 필드 추가가 이 경로). 필드 rename/타입 변경/삭제 같은
// 구조 변경 시에만 V2 를 새로 정의하고 KickLogMigrationPlan.stages 에 stage 를 추가한다.
enum KickLogSchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)

    static var models: [any PersistentModel.Type] {
        [
            User.self,
            Match.self,
            QuarterWorkout.self,
            Venue.self,
            Friend.self,
            FriendMatch.self,
            FriendQuarterWorkout.self,
            HealthKitState.self,
        ]
    }
}

// 마이그레이션 플랜. 현재는 V1 단일 버전이라 stages 비어 있음 (마이그레이션 불필요).
enum KickLogMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [KickLogSchemaV1.self]
    }

    static var stages: [MigrationStage] {
        []
    }
}

// MARK: - 모든 모델 타입 — ModelContainer 등록용 (Preview·in-memory 컨테이너 호환)

enum KickLogSchema {
    static let allModels: [any PersistentModel.Type] = KickLogSchemaV1.models
}

// MARK: - ModelContext 저장 헬퍼

extension ModelContext {
    /// 저장 실패를 침묵시키지 않고 로그를 남긴다. iOS 가 1차 SoT 라 로컬 저장 실패는 곧 데이터 유실.
    func saveOrLog(caller: String) {
        do { try save() } catch {
            print("[SwiftData] 저장 실패 (\(caller)): \(error)")
        }
    }
}
