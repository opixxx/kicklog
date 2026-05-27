# ADR-0004: SwiftData 모델 + HealthKit 매핑

- **Status**: Accepted
- **Date**: 2026-05-21
- **선행 ADR**: ADR-0001 (MVP 스코프), ADR-0003 (데이터 모델 + API)

## Context

ADR-0003에서 백엔드 데이터 모델과 동기화 정책(D9: iOS가 1차 SoT, fire-and-forget)이 결정. iOS 쪽 SwiftData 모델 디자인·HealthKit 권한·Observer Query·시간대·친구 캐시 정책·분석 위치가 미정.

**스코프 안**:
- SwiftData `@Model` 디자인 (서버 스키마 매핑)
- HealthKit 권한 set + Info.plist 문자열
- HealthKit Observer Query / Background Delivery
- 시간대 처리
- 친구 데이터 캐시 정책
- 사용자 프로필 (키·몸무게·생년월일) 처리
- 분석 결과 저장 위치 (SwiftData vs 매번 재계산)

**스코프 밖** (후속 ADR):
- 자동 그룹핑 시간/위치 임계값 → **ADR-0002**
- 초대 링크 Universal Link AASA 구조 → **ADR-0005**

---

## Decisions

### D1. iCloud Sync (SwiftData + CloudKit) — **미도입 (MVP)**

- **선택**: (A) `.cloudKitDatabase: .none` (기본값) — 순수 로컬 SwiftData
- **고려한 옵션**: (A) 미도입, (B) 전체 도입, (C) 부분 도입
- **이유**:
  - MVP는 iPhone only (ADR-0003 D9): 멀티 디바이스 동기화 대상 없음
  - iOS 자동 백업(iCloud Backup)에 SwiftData DB 포함 → 폰 교체 시 복원 가능
  - `@Model` 디자인 자유도 (CloudKit 제약 회피: nullable·default value·relationship 제약)
  - 백엔드 SoT 정책과 일관성 — 멀티 디바이스 동기화는 서버 fetch로 처리
- **v1.1+**: iPad 지원 진짜 필요해지면 `.cloudKitDatabase: .automatic`으로 마이그레이션 (기존 데이터는 새 CloudKit container로 1회 마이그레이션)

### D2. SwiftData 모델 구조 — **본인/친구 분리 + MatchDisplayable protocol**

- **선택**: (B) `Match` (본인, 편집 가능) ↔ `FriendMatch` (친구, read-only 캐시) 별도 모델
- **고려한 옵션**: (A) 단일 모델 + `ownerUserId` 필드, (B) 분리 (선택), (C) 친구는 in-memory만
- **이유**:
  - **책임 명확**: 본인 = 편집 가능 + syncedAt 필드, 친구 = read-only + cachedAt
  - **삭제 정책 분리**: 본인 Match는 영구 보존, FriendMatch는 캐시 TTL/친구 끊기 cleanup
  - **친구 끊기 시 cleanup**: `DELETE FROM FriendMatch WHERE friendUserId = X` 단순
  - SwiftUI 컴포넌트 재사용은 `MatchDisplayable` protocol로 해결

### D3. HealthKit 권한 set — **최소 6개**

- **선택**: 분석에 꼭 필요한 6개만
- **목록**:
  - `HKObjectType.workoutType()` (Soccer 감지)
  - `HKQuantityType(.heartRate)` (심박수)
  - `HKQuantityType(.distanceWalkingRunning)` (이동거리)
  - `HKQuantityType(.activeEnergyBurned)` (활성 에너지)
  - `HKQuantityType(.runningSpeed)` (속도, iOS 17+)
  - `HKSeriesType.workoutRoute()` (GPS 경로)
- **고려한 옵션**: (A) 최소 6개 (선택), (B) +사용자 프로필 4개 = 10개, (C) +확장 = 15+
- **이유**:
  - Apple 심사 정책: "필요한 만큼만"
  - 사용자 허용률↑ (권한 화면 짧음)
  - 칼로리는 `ActiveEnergyBurned`(HealthKit이 사용자 프로필로 자동 계산)을 그대로 사용
  - v1.1+ 코칭 기능 도입 시 권한 확장 (`requestAuthorization` 재호출)

#### Info.plist 문자열
```xml
<key>NSHealthShareUsageDescription</key>
<string>축구 경기 데이터를 분석해 거리·속도·심박수·쿼터별 체력 변화 리포트를 제공합니다.</string>

<key>NSHealthUpdateUsageDescription</key>
<string>KickLog는 HealthKit 데이터를 수정하지 않습니다. (현재 미사용)</string>
```

### D4. HealthKit Observer Query — **Background Delivery 활성**

- **선택**: (B) `HKObserverQuery` + `enableBackgroundDelivery(for:frequency: .immediate)`
- **고려한 옵션**: (A) Foreground only, (B) Background Delivery (선택), (C) Foreground Observer
- **이유**:
  - PRD 결정과 일치: "Observer Query: 백그라운드 자동 import"
  - 사용자 마찰 0 — 앱 열면 라벨링 카드 이미 표시
  - HealthKit Background Delivery는 system event 기반 → 배터리 영향 미미
  - `HKAnchoredObjectQuery`로 incremental fetch (anchor 영구 저장)
  - 푸시 알림은 v1.1+ — MVP는 import만, 알림 X

#### Capabilities
- Background Modes: ☑ Background fetch, ☑ Background processing

### D5. 시간대 처리 — **UTC 저장 + Local TZ 표시**

- **선택**: (A) Swift `Date` (internally UTC) + 표시 시 `Locale.current` / `TimeZone.current` 자동
- **고려한 옵션**: (A) UTC+Local (선택), (B) Local 저장 + TZ 메타, (C) UTC + KST 강제
- **이유**:
  - PostgreSQL `TIMESTAMPTZ` + Swift `Date` 자연 통일 (ADR-0003)
  - 표준 패턴, 글로벌 확장 시 변경 없음
  - 시즌 분류는 사용자 현재 TZ 기준 — 해외 여행 중 뛴 경기도 그 시점 local 일자

### D6. 친구 데이터 캐시 정책 — **1시간 TTL + 캐시-우선 + 풀투리프레시**

- **선택**: (B) `cacheTTL = 3600s`, 화면 진입 시 캐시 즉시 표시 + TTL 초과 시 백그라운드 refresh, 사용자가 풀투리프레시로 강제 새로고침
- **고려한 옵션**: (A) 5분, (B) 1시간 (선택), (C) 24시간, (D) 매번 fetch
- **이유**:
  - 본인+팀원은 주 1~2회 경기 — 신선도 < 네트워크 절감
  - 캐시-우선으로 화면 진입 빈 화면 없음
  - 풀투리프레시로 사용자 통제권
  - 푸시 알림 도입 시 (v1.1+) 친구 새 경기 알림 받으면 `cachedAt = .distantPast`로 TTL 강제 만료

### D7. 사용자 프로필 (키·몸무게·생년월일) — **MVP에서 사용 안 함**

- **선택**: (A) HealthKit에서 read 안 함, 프로필 화면에 표시 안 함
- **고려한 옵션**: (A) 안 받음 (선택), (B) HealthKit 자동 read, (C) 옵셔널 권한, (D) 사용자 수동 입력
- **이유**:
  - KickLog 분석에 키·몸무게 불필요 — `ActiveEnergyBurned`는 HealthKit이 사용자 프로필로 자동 계산
  - D3 최소 권한 일관성
  - 프로필 화면 단순화: `display_name` + 가입일 + 친구 수 + 시즌 통계만
  - v1.1+ 코칭 기능 도입 시 권한 확장
- **PRD 정정**: PRD 4.7 "사용자 프로필 HealthKit 자동 read" → "MVP에서 사용 안 함"으로 갱신

### D8. 분석 결과 위치 — **SwiftData 영속 캐시 + Trim 시 재계산**

- **선택**: (A) 첫 import 시 한 번 계산 → `QuarterWorkout` 집계 필드에 영속 저장, trim 시 재계산
- **고려한 옵션**: (A) 영속 캐시 (선택), (B) 매번 재계산, (C) Hybrid + `algorithmVersion`
- **이유**:
  - ADR-0003 D5와 일관 — Match/QuarterWorkout 집계 필드 이미 서버에도 저장
  - 성능 — 매 경기 카드 17개 즉시 표시 (raw 재계산은 1~2초). 시즌 통계 derive 위치는 D9 참조
  - MVP 알고리즘 안정 (스프린트 14 km/h 절대 임계, ADR-0001 D8)
  - v1.1+ 개인화 임계 도입 시 (C) Hybrid로 진화 (`algorithmVersion` 컬럼 추가)

### D9. 본인 시즌 통계 derive — **백엔드 API 호출 (iOS SwiftData reduce X)**

- **선택**: (A2) 매 경기 카드 = SwiftData / 본인·친구 시즌 통계 = 백엔드 `GET /users/:userId/seasons/:year`
- **고려한 옵션**:
  - (A1) 양쪽 백엔드 — 매 경기 카드까지 백엔드 fetch
  - (A2) 하이브리드 — 매 경기는 SwiftData, 시즌은 백엔드 (선택)
  - (B) 양쪽 iOS — 시즌도 SwiftData reduce
- **이유**:
  - **알고리즘 단일 소스** — 본인/친구 시즌 집계가 Kotlin 1벌. Swift reduce 미구현으로 언어 간 divergence 위험 0
  - **시즌은 가끔 보는 화면** — 매 경기 카드의 즉각성과 달리 PUT 완료 후 정합으로 충분
  - **백엔드 코드 재사용** — `SeasonStatService.calculate()`가 본인/친구 동일 (PR #11에서 구현됨)
  - 매 경기 카드는 SwiftData 그대로 유지 — D8 결정 보존
- **트레이드오프**:
  - 시즌 통계는 **오프라인 시 표시 불가** (매 경기 카드는 SwiftData로 정상 표시)
  - **PUT 미완료 경기 = 시즌 합계 누락** — ADR-0003 D9 "동기화 대기 N건" 배너로 사용자 인지 채널 제공
- **v1.1+ 후보**: 시즌 통계도 iOS SwiftData reduce로 이전 (오프라인 가치 vs 코드 2벌 부담 재평가 시)

---

## SwiftData @Model 정의 (전체)

```swift
import SwiftData
import Foundation

// ─── 본인 (편집 가능, 동기화 대상) ────────────────────

@Model
final class User {
    @Attribute(.unique) var serverId: Int64
    var displayName: String
    var email: String?
    var createdAt: Date
    var lastSyncedAt: Date?
}

@Model
final class Match {
    @Attribute(.unique) var clientMatchId: UUID
    var serverId: Int64?                            // 동기화 후 받음
    var playedAt: Date                              // UTC
    var venueId: Int64?                             // Venue.serverId 참조
    var opponentName: String?
    var result: String?                             // "W" | "D" | "L" | nil
    var position: String?                           // "GK" | "DF" | "MF" | "FW" | nil
    var userGoals: Int?
    var userAssists: Int?
    // 헤드라인 4지표 (D8 캐시)
    var totalDistanceM: Int
    var maxSpeedKmh: Double
    var sprintCount: Int
    var avgHeartRate: Int
    // 동기화 상태
    var labeledAt: Date?                            // 사용자가 라벨링 완료 시각
    var syncedAt: Date?                             // 서버 업로드 완료
    var lastSyncAttemptAt: Date?
    var syncErrorMessage: String?
    // 관계
    @Relationship(deleteRule: .cascade, inverse: \QuarterWorkout.match)
    var quarters: [QuarterWorkout] = []
}

@Model
final class QuarterWorkout {
    @Attribute(.unique) var sourceWorkoutUUID: String   // HealthKit HKWorkout.uuid
    var quarterNo: Int                                   // 1~4
    var startedAt: Date
    var endedAt: Date
    var durationSeconds: Int
    // 쿼터별 집계 (D8 캐시)
    var distanceM: Int
    var avgSpeedKmh: Double
    var avgHeartRate: Int
    var maxHeartRate: Int
    var sprintCount: Int
    var activeEnergyKcal: Int
    var trimmed: Bool = false
    var match: Match?
}

@Model
final class Venue {
    @Attribute(.unique) var serverId: Int64
    var name: String
    var geoLat: Double
    var geoLng: Double
    var createdAt: Date
}

// ─── 친구 (read-only 캐시) ────────────────────────────

@Model
final class Friend {
    @Attribute(.unique) var friendUserId: Int64
    var displayName: String
    var friendshipStatus: String                    // "pending" | "accepted"
    var initiatedByMe: Bool
    var lastFetchedAt: Date?
}

@Model
final class FriendMatch {
    @Attribute(.unique) var serverId: Int64
    var friendUserId: Int64
    var playedAt: Date
    var venueName: String?                          // 친구의 venue 이름 (서버에서 join)
    var opponentName: String?
    var result: String?
    var position: String?
    var userGoals: Int?
    var userAssists: Int?
    // 헤드라인
    var totalDistanceM: Int
    var maxSpeedKmh: Double
    var sprintCount: Int
    var avgHeartRate: Int?                          // 친구가 hide 시 nil
    // 캐시
    var cachedAt: Date
    @Relationship(deleteRule: .cascade, inverse: \FriendQuarterWorkout.friendMatch)
    var quarters: [FriendQuarterWorkout] = []
}

@Model
final class FriendQuarterWorkout {
    @Attribute(.unique) var serverId: Int64
    var quarterNo: Int
    var distanceM: Int
    var avgSpeedKmh: Double
    var avgHeartRate: Int?                          // hide 시 nil
    var sprintCount: Int
    var friendMatch: FriendMatch?
}

// ─── 친구 초대 (본인 발급) ────────────────────────────

@Model
final class FriendInvitation {
    @Attribute(.unique) var token: String
    var expiresAt: Date
    var useCount: Int
    var createdAt: Date
}

// ─── HealthKit Anchor (Observer Query용) ───────────────

@Model
final class HealthKitState {
    @Attribute(.unique) var key: String             // "workoutAnchor"
    var anchorData: Data?                            // HKQueryAnchor → NSKeyedArchiver
    var lastFetchedAt: Date?
}

// ─── 공통 protocol (SwiftUI 컴포넌트 재사용) ──────────

protocol MatchDisplayable {
    var playedAt: Date { get }
    var venueDisplayName: String? { get }
    var opponentName: String? { get }
    var result: String? { get }
    var totalDistanceM: Int { get }
    var maxSpeedKmh: Double { get }
    var sprintCount: Int { get }
    var displayedAvgHeartRate: Int? { get }         // 친구가 hide 시 nil
}

extension Match: MatchDisplayable {
    var venueDisplayName: String? { /* Venue.name from venueId */ }
    var displayedAvgHeartRate: Int? { avgHeartRate }
}

extension FriendMatch: MatchDisplayable {
    var venueDisplayName: String? { venueName }
    var displayedAvgHeartRate: Int? { avgHeartRate }
}
```

---

## HealthKit Service 구현 윤곽

### Observer Query 등록 (D4)

```swift
@MainActor
class HealthKitService {
    let store = HKHealthStore()
    private let readTypes: Set<HKObjectType> = [
        HKObjectType.workoutType(),
        HKQuantityType(.heartRate),
        HKQuantityType(.distanceWalkingRunning),
        HKQuantityType(.activeEnergyBurned),
        HKQuantityType(.runningSpeed),
        HKSeriesType.workoutRoute(),
    ]
    
    func requestAuthorization() async throws {
        try await store.requestAuthorization(toShare: [], read: readTypes)
    }
    
    func startObserver() async throws {
        let workoutType = HKObjectType.workoutType()
        
        // 1. Observer Query: 새 워크아웃 발생 시 트리거
        let observer = HKObserverQuery(sampleType: workoutType, predicate: nil) { 
            [weak self] _, completion, _ in
            Task { @MainActor in
                await self?.importNewSoccerWorkouts()
                completion()
            }
        }
        store.execute(observer)
        
        // 2. Background Delivery
        try await store.enableBackgroundDelivery(for: workoutType, frequency: .immediate)
    }
    
    private func importNewSoccerWorkouts() async {
        let predicate = HKQuery.predicateForWorkouts(with: .soccer)
        let anchor = await loadAnchor()
        
        let query = HKAnchoredObjectQuery(
            type: .workoutType(),
            predicate: predicate,
            anchor: anchor,
            limit: HKObjectQueryNoLimit
        ) { [weak self] _, samples, _, newAnchor, _ in
            guard let workouts = samples as? [HKWorkout] else { return }
            Task { @MainActor in
                await self?.saveAnchor(newAnchor)
                await self?.importer.importAll(workouts: workouts)
            }
        }
        store.execute(query)
    }
}
```

### 분석 + SwiftData 저장 (D8)

```swift
@MainActor
class WorkoutImporter {
    let modelContext: ModelContext
    let analyzer: WorkoutAnalyzer
    
    func importAll(workouts: [HKWorkout]) async {
        for workout in workouts {
            await importOne(workout: workout)
        }
    }
    
    private func importOne(workout: HKWorkout) async {
        // 이미 import됐는지 확인 (HealthKit UUID UNIQUE)
        let existing = try? modelContext.fetch(
            FetchDescriptor<QuarterWorkout>(
                predicate: #Predicate { $0.sourceWorkoutUUID == workout.uuid.uuidString }
            )
        ).first
        if existing != nil { return }
        
        // 분석 (D8 — raw → 집계)
        let metrics = await analyzer.analyze(workout: workout)
        
        // SwiftData 저장
        let quarter = QuarterWorkout(
            sourceWorkoutUUID: workout.uuid.uuidString,
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
        
        // 자동 그룹핑 → Match에 연결 (ADR-0002 임계값 결정 후 구현)
        // await groupingService.assignToMatch(quarter)
        
        try? modelContext.save()
    }
}
```

### Trim 시 재계산 (D8)

```swift
extension QuarterWorkout {
    func retrim(newStart: Date, newEnd: Date, analyzer: WorkoutAnalyzer, healthStore: HKHealthStore) async {
        guard let workout = await fetchHKWorkout(uuid: sourceWorkoutUUID, store: healthStore) else { return }
        
        let metrics = await analyzer.analyze(workout: workout, range: newStart...newEnd)
        
        startedAt = newStart
        endedAt = newEnd
        durationSeconds = Int(newEnd.timeIntervalSince(newStart))
        distanceM = metrics.distanceM
        avgSpeedKmh = metrics.avgSpeedKmh
        avgHeartRate = metrics.avgHeartRate
        maxHeartRate = metrics.maxHeartRate
        sprintCount = metrics.sprintCount
        activeEnergyKcal = metrics.activeEnergyKcal
        trimmed = true
        
        match?.recalculateHeadlineMetrics()
        try? match?.modelContext?.save()
    }
}

extension Match {
    func recalculateHeadlineMetrics() {
        guard !quarters.isEmpty else { return }
        totalDistanceM = quarters.reduce(0) { $0 + $1.distanceM }
        maxSpeedKmh = quarters.map(\.avgSpeedKmh).max() ?? 0
        sprintCount = quarters.reduce(0) { $0 + $1.sprintCount }
        let totalDuration = quarters.reduce(0) { $0 + $1.durationSeconds }
        avgHeartRate = totalDuration > 0
            ? Int(quarters.reduce(0.0) { $0 + Double($1.avgHeartRate) * Double($1.durationSeconds) } / Double(totalDuration))
            : 0
    }
}
```

---

## 친구 캐시 정책 구현 (D6)

```swift
@MainActor
class FriendDataService {
    private let cacheTTL: TimeInterval = 3600       // 1시간
    
    func loadFriendSeasonStats(friendUserId: Int64, year: Int) async throws -> SeasonStats {
        let friend = try modelContext.fetch(
            FetchDescriptor<Friend>(predicate: #Predicate { $0.friendUserId == friendUserId })
        ).first
        
        // 캐시 신선도 확인
        if let lastFetched = friend?.lastFetchedAt,
           Date().timeIntervalSince(lastFetched) < cacheTTL,
           let stats = await loadCachedStats(friendUserId: friendUserId, year: year) {
            return stats
        }
        
        // 만료 → API fetch
        let stats = try await api.getFriendSeasonStats(friendUserId: friendUserId, year: year)
        await saveCachedStats(friendUserId: friendUserId, year: year, stats: stats)
        friend?.lastFetchedAt = Date()
        try? modelContext.save()
        return stats
    }
    
    func refreshFriend(friendUserId: Int64) async throws {
        let stats = try await api.getFriendSeasonStats(...)
        let matches = try await api.getFriendMatches(friendUserId: friendUserId, limit: 20)
        // SwiftData 업데이트 (UPSERT)
    }
    
    func removeFriend(friendUserId: Int64) async throws {
        try await api.deleteFriendship(friendUserId: friendUserId)
        
        // 로컬 cascade 삭제
        let friend = try modelContext.fetch(
            FetchDescriptor<Friend>(predicate: #Predicate { $0.friendUserId == friendUserId })
        ).first
        if let friend = friend { modelContext.delete(friend) }
        
        let friendMatches = try modelContext.fetch(
            FetchDescriptor<FriendMatch>(predicate: #Predicate { $0.friendUserId == friendUserId })
        )
        friendMatches.forEach { modelContext.delete($0) }
        
        try modelContext.save()
    }
}
```

---

## 시간대 디스플레이 표준 (D5)

| 위치 | 형식 | 예시 (KST) |
|---|---|---|
| 경기 리스트 | `yyyy. M. d. (E) a h:mm` | `2026. 5. 21. (수) 오전 9:00` |
| 경기 리포트 헤더 | `yyyy년 M월 d일 (E) HH:mm` | `2026년 5월 21일 (수) 09:00` |
| 시즌 카드 | `yyyy 시즌` | `2026 시즌` |
| 상대 시간 | `RelativeDateTimeFormatter` | `2시간 전`, `3일 전` |

---

## Consequences

### 긍정
- **iOS가 1차 SoT 정책 명확** (ADR-0003 D9와 일관)
- **본인/친구 모델 분리**로 책임 명확 + 친구 끊기 cleanup 단순
- **Background Delivery**로 사용자 마찰 0
- **분석 결과 SwiftData 캐시**로 시즌 통계 즉시 표시
- **CloudKit 의존성 없음** — MVP 일정 단축, 제약 없음
- **HealthKit 최소 권한** — Apple 심사 안전 + 허용률↑

### 부정 / 트레이드오프
- **iCloud Sync 없음** — iPad 추가 시 v1.1 마이그레이션 비용
- **친구 캐시 TTL 1시간** — 매우 활발한 사용자 시나리오에서 신선도 부족 가능 (v1.1 푸시 알림으로 보완)
- **trim 시 재계산** — 사용자가 slider로 자르면 HealthKit raw 재fetch 필요 (네트워크 X but 메모리 비용)
- **HKAnchoredObjectQuery anchor 영속화** — 손상 시 모든 HealthKit 데이터 재import (1회성 비용)
- **사용자 프로필 표시 없음** — v1.1까지 프로필 화면이 단순 (display_name + 통계만)

### v1.1+ 마이그레이션 후보
- iCloud Sync (`.cloudKitDatabase: .automatic`) — iPad 지원
- 푸시 알림 — 친구 새 경기, 친구 요청
- 사용자 프로필 (키·몸무게·생년월일) — 코칭 기능 도입과 함께
- 분석 알고리즘 버전 관리 (`algorithmVersion` 컬럼)
- 운동장 히트맵 (`heatmap_grid_json` 추가)

---

## Revisions

| 날짜 | 변경 | 사유 |
|---|---|---|
| 2026-05-21 | 초기 작성 | grill-me 인터뷰 D1~D8 |
| 2026-05-21 | PRD 4.7 정정 (D7) — 사용자 프로필 HealthKit read 안 함 | D3 최소 권한 결정과 충돌 → 일관성 유지 |
| 2026-05-24 | D8 표현 명확화 + D9 신설 — 본인 시즌 통계는 백엔드 API 호출 (A2 하이브리드) | grill-me 후속 결정 — 백엔드 `SeasonStatService` 이미 구현 (PR #11), 묵시적 (A2) 미끄러짐을 명시화 |
