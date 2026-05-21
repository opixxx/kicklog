---
name: ios-conventions
description: KickLog iOS(Swift 5.10+ / SwiftUI / SwiftData / HealthKit) 코딩 컨벤션 — 한글 주석, Swift API Design Guidelines, SwiftUI 패턴, async/await, Apple HIG. ios-reviewer 에이전트가 사전 로드한다.
user-invocable: false
---

# KickLog iOS 코딩 컨벤션 (Swift / SwiftUI / SwiftData / HealthKit)

> 본 스킬은 `ios-reviewer` agent의 `skills:` 필드로 사전 로드된다.
> 직접 호출 X (`user-invocable: false`).
> 백엔드 컨벤션은 별도 (`coding-conventions` skill).

---

## 1. 언어 규칙 (백엔드와 동일 원칙)

| 대상 | 언어 |
|:----|:----|
| 식별자 (변수·함수·struct·class) | 영문 (Swift API Design Guidelines) |
| 주석 / DocC | 한글 |
| 로그 메시지 | 한글 (`os.Logger` 사용) |
| 사용자 표시 텍스트 | 한글 (Localizable.strings — v1.1+ 다국어) |
| Error 메시지 | 한글 |

```swift
// ✅
/// 사용자가 trim 슬라이더로 쿼터 시작/종료 시각을 조정했을 때 재계산.
func retrim(newStart: Date, newEnd: Date) async {
    logger.info("쿼터 재계산 시작: quarterNo=\(quarterNo), range=\(newStart)...\(newEnd)")
    // ...
}

// ❌
/// Retrim the quarter when user adjusted the slider.
func retrim(newStart: Date, newEnd: Date) async {
    print("Retrim quarter \(quarterNo)")
}
```

## 2. 디렉토리 구조 (KickLog iOS)

```
ios/KickLog/
├── App/                        # @main, 온보딩, 메인 탭바
│   ├── KickLogApp.swift
│   ├── ContentView.swift       # 탭바 root
│   └── Onboarding/             # 4페이지 온보딩
├── Models/                     # SwiftData @Model
│   ├── User.swift
│   ├── Match.swift
│   ├── QuarterWorkout.swift
│   ├── Venue.swift
│   ├── Friend.swift
│   ├── FriendMatch.swift
│   ├── FriendQuarterWorkout.swift
│   ├── FriendInvitation.swift
│   ├── HealthKitState.swift
│   └── MatchDisplayable.swift  # protocol
├── Features/
│   ├── Games/                  # 경기 탭
│   │   ├── GameListView.swift
│   │   ├── GameDetailView.swift
│   │   ├── LabelingView.swift
│   │   └── TrimSliderView.swift
│   ├── Season/                 # 시즌 탭
│   │   ├── SeasonView.swift
│   │   └── SeasonCard.swift
│   ├── Friends/                # 친구 탭
│   │   ├── FriendListView.swift
│   │   ├── FriendDetailView.swift
│   │   ├── InvitationLinkView.swift
│   │   └── InvitationAcceptView.swift
│   └── Settings/               # 설정 탭
├── Services/                   # 외부 서비스 + API
│   ├── HealthKitService.swift  # Observer Query + 권한
│   ├── WorkoutImporter.swift   # HK raw → SwiftData
│   ├── WorkoutAnalyzer.swift   # 집계 지표 계산
│   ├── LocationService.swift   # CoreLocation
│   ├── APIClient.swift         # 백엔드 통신
│   ├── AuthService.swift       # Sign in with Apple + Kakao + JWT
│   └── FriendDataService.swift # 친구 캐시 정책
├── Components/                 # 재사용 UI
│   ├── MatchCard.swift
│   ├── QuarterBarChart.swift   # Swift Charts
│   └── SeasonStatCard.swift
├── Utils/
│   ├── DateFormatter+KR.swift
│   └── Logger+KickLog.swift
└── Resources/
    ├── Assets.xcassets
    └── Localizable.strings (v1.1)
```

## 3. SwiftUI 패턴

### 3.1 View 구조 (단순함 우선)
```swift
// ✅ View struct + @Observable ViewModel
struct GameDetailView: View {
    let match: Match
    @State private var viewModel: GameDetailViewModel

    init(match: Match) {
        self.match = match
        self._viewModel = State(initialValue: GameDetailViewModel(match: match))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                MatchHeaderView(match: match)
                MetricsSummaryView(metrics: viewModel.summaryMetrics)
                QuarterBarChart(quarters: match.quarters)
                MetadataView(match: match)
            }
            .padding()
        }
        .navigationTitle("경기 리포트")
    }
}

@Observable
final class GameDetailViewModel {
    let match: Match
    var summaryMetrics: SummaryMetrics

    init(match: Match) {
        self.match = match
        self.summaryMetrics = SummaryMetrics.from(match: match)
    }
}
```

### 3.2 상태 관리 패턴
- **간단한 화면**: `@State` 만으로 충분
- **공유 상태**: `@Observable` class + `@State` 또는 `@Environment`
- **`@StateObject`** / **`@ObservedObject`** 는 iOS 17+에선 `@Observable` 우선

### 3.3 SwiftUI 안티패턴
```swift
// ❌ View body 안에서 무거운 계산
var body: some View {
    let stats = match.quarters.reduce(into: ...) { ... }  // 매 렌더링마다 계산
    return Text(stats.description)
}

// ✅ ViewModel 또는 computed property에 캐시
@State private var stats: Stats = []
```

```swift
// ❌ View hierarchy 너무 깊음 (NavigationLink 안에 또 NavigationStack)
// ✅ NavigationStack은 root에 1개. 내부는 NavigationLink + path 관리.
```

## 4. SwiftData 사용

### 4.1 @Model 정의 (ADR-0004 D2 결정)
```swift
import SwiftData

@Model
final class Match {
    @Attribute(.unique) var clientMatchId: UUID
    var serverId: Int64?
    var playedAt: Date
    // ...
    @Relationship(deleteRule: .cascade, inverse: \QuarterWorkout.match)
    var quarters: [QuarterWorkout] = []
}
```

- **`@Attribute(.unique)`** — UNIQUE 제약
- **`@Relationship(deleteRule: .cascade)`** — 부모 삭제 시 자식 자동
- **inverse: \KeyPath** — 양방향 관계 명시 (성능 + Xcode 자동완성)

### 4.2 쿼리 패턴
```swift
// ✅ #Predicate 매크로 (컴파일 타임 검증)
@Query(filter: #Predicate<Match> { $0.syncedAt == nil },
       sort: [SortDescriptor(\.playedAt, order: .reverse)])
private var unsyncedMatches: [Match]

// 또는 명시적 fetch
let descriptor = FetchDescriptor<Match>(
    predicate: #Predicate { $0.playedAt >= startOfYear },
    sortBy: [SortDescriptor(\.playedAt, order: .reverse)]
)
let matches = try modelContext.fetch(descriptor)
```

### 4.3 save 호출 시점
- 명시적 변경 후 즉시 `try modelContext.save()`
- 다만 너무 잦은 save는 성능 저하 — batch 처리 가능

## 5. HealthKit (ADR-0004 D3, D4)

### 5.1 권한 요청
```swift
let readTypes: Set<HKObjectType> = [
    HKObjectType.workoutType(),
    HKQuantityType(.heartRate),
    HKQuantityType(.distanceWalkingRunning),
    HKQuantityType(.activeEnergyBurned),
    HKQuantityType(.runningSpeed),
    HKSeriesType.workoutRoute(),
]

try await store.requestAuthorization(toShare: [], read: readTypes)
```

### 5.2 Observer Query + Background Delivery
```swift
let observer = HKObserverQuery(sampleType: .workoutType(), predicate: nil) { _, completion, _ in
    Task { @MainActor in
        await importer.importNewWorkouts()
        completion()  // ← 반드시 호출
    }
}
store.execute(observer)
try await store.enableBackgroundDelivery(for: .workoutType(), frequency: .immediate)
```

### 5.3 HealthKit 안티패턴
- ❌ `store.requestAuthorization` 결과로 권한 여부 판단 (Apple privacy: 거부 사실 알려주지 않음)
- ❌ Main thread에서 큰 HKAnchoredObjectQuery 동기 실행
- ❌ Observer Query `completion` 호출 누락 → 시스템이 throttle

## 6. Swift Concurrency (async/await)

### 6.1 actor / @MainActor
```swift
@MainActor
final class HealthKitImporter {
    // UI 업데이트 + SwiftData ModelContext 접근은 @MainActor에서
    var modelContext: ModelContext
    
    func importAll(workouts: [HKWorkout]) async {
        for workout in workouts {
            await importOne(workout)
        }
    }
}
```

### 6.2 Task / TaskGroup
```swift
// 친구 N명 동시 fetch
await withTaskGroup(of: SeasonStats?.self) { group in
    for friend in friends {
        group.addTask {
            try? await api.getFriendSeasonStats(friendUserId: friend.id, year: year)
        }
    }
    for await result in group { ... }
}
```

### 6.3 Concurrency 안티패턴
- ❌ `DispatchQueue.main.async` (Swift 6는 deprecated 방향)
- ❌ `Task { }` 안에서 `[weak self]` 누락 → retain cycle
- ❌ `await` 결과를 무시 (`_ = try? await ...`) — 에러 silent

## 7. 명명 규칙 (Swift API Design Guidelines)

| 대상 | 패턴 | 예시 |
|---|---|---|
| Type (struct/class/enum) | `UpperCamelCase` | `Match`, `WorkoutAnalyzer` |
| Property/Method | `lowerCamelCase` | `playedAt`, `recalculateHeadlineMetrics()` |
| Protocol | 명사 또는 `-able`/`-ible` | `MatchDisplayable`, `Identifiable` |
| Action method | 동사 시작 | `fetchMatches()`, `removeFriend(friendUserId:)` |
| Boolean property | `is`, `has`, `should`, `can` | `isSynced`, `hasQuarter1` |
| Enum case | `lowerCamelCase` | `case accepted, pending` |
| Generic | 한 글자 또는 의미있는 명사 | `T`, `Element`, `View` |

## 8. Error 처리

```swift
// ✅ throws + 도메인 에러
enum KickLogError: LocalizedError {
    case unauthorized
    case notFoundMatch
    case syncFailed(reason: String)
    case healthKitDenied
    
    var errorDescription: String? {
        switch self {
        case .unauthorized: "인증이 필요합니다"
        case .notFoundMatch: "경기를 찾을 수 없습니다"
        case .syncFailed(let reason): "동기화 실패: \(reason)"
        case .healthKitDenied: "HealthKit 권한이 거부되었습니다. 설정 → 개인정보 보호 → 건강에서 허용해주세요"
        }
    }
}

// ✅ Result type — 명시적 성공/실패 (다만 throws 권장)
func validateToken(_ token: String) -> Result<UserId, KickLogError> { ... }
```

## 9. 로그

```swift
// Utils/Logger+KickLog.swift
import os.log

extension Logger {
    static let sync = Logger(subsystem: "com.opixxx.kicklog", category: "sync")
    static let healthKit = Logger(subsystem: "com.opixxx.kicklog", category: "healthKit")
    static let auth = Logger(subsystem: "com.opixxx.kicklog", category: "auth")
}

// ✅
Logger.sync.info("경기 업로드 완료: matchId=\(match.serverId ?? 0)")
Logger.healthKit.error("Observer Query 실패: \(error.localizedDescription)")

// ❌
print("경기 업로드 완료")  // 프로덕션에 print 금지
```

## 10. Apple HIG (Human Interface Guidelines)

- **Dynamic Type**: 모든 텍스트는 SF Pro + Dynamic Type 지원 (`.font(.body)`, `.title2` 등)
- **Dark Mode**: Color는 시스템 색상 또는 Color Set으로
- **Safe Area**: 자동 (`.ignoresSafeArea`는 신중)
- **Haptic Feedback**: 중요한 액션에 `UIImpactFeedbackGenerator` (예: 친구 수락, 라벨링 완료)
- **VoiceOver**: 핵심 인터랙티브 요소에 `.accessibilityLabel("...")` 추가
- **버튼 hit area**: 최소 44×44pt

## 11. 성능

- **`@Query`는 main actor에서만**
- **이미지는 thumbnail 우선** — `.aspectRatio(contentMode: .fill).frame(...)` + `.clipped()`
- **LazyVStack / LazyVGrid** — 긴 리스트는 lazy
- **List는 SwiftUI 기본 lazy** — VStack 안에서 100개 row 그리지 말 것

## 12. 안티패턴 (KickLog 컨텍스트)

| Anti-pattern | 대안 |
|---|---|
| `@StateObject` 사용 (iOS 17+) | `@State + @Observable` |
| View body 안에서 무거운 계산 | ViewModel에 캐시 |
| `print()` 프로덕션 로그 | `Logger` (os.log) |
| `Force unwrap (!)` 비즈니스 로직 | `guard let / if let / try?` |
| `DispatchQueue.main.async` | `@MainActor` + `await` |
| 모든 화면에 `@AppStorage` | UserDefaults 직접 + Service 레이어 |
| HealthKit 권한 거부 명시 안 함 | KickLogError.healthKitDenied + 안내 |
| `Color.red`/`Color.blue` 하드코딩 | Color Set (다크 모드 + 브랜드 컬러) |
| 친구 데이터 캐시 무시 | FriendDataService 경유 (D6 TTL) |

## 13. 참조

- ADR-0001: MVP 스코프 (`docs/adr/0001-mvp-scope.md`)
- ADR-0003: 데이터 모델 + API (`docs/adr/0003-data-model-and-api.md`)
- ADR-0004: SwiftData + HealthKit (`docs/adr/0004-swiftdata-and-healthkit.md`)
- Apple Swift API Design Guidelines: https://swift.org/documentation/api-design-guidelines/
- Apple HIG: https://developer.apple.com/design/human-interface-guidelines/

---

> **백엔드 컨벤션**은 `coding-conventions` skill (Kotlin/Spring 전용).
> 본 스킬은 iOS Swift 전용.
