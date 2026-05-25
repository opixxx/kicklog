import Foundation

// 더미 단계 모델 — 추후 SwiftData @Model + 백엔드 API 응답 모델로 교체 예정.
// JSX 와이어프레임의 matches 배열 구조를 그대로 따른다.
struct SampleMatch: Identifiable, Hashable {
    let id = UUID()
    let dateNum: String       // "5/18" — 와이어프레임 표기 그대로
    let dow: String           // "수" / "일"
    let opponent: String      // "FC블루스"
    let venue: String         // "마포 풋살장"
    let result: MatchResult
    let score: String         // "4-2"
    let distanceKm: Double    // 3.2
    let avgSpeedKmh: Double   // 19.4
    let sprintCount: Int      // 14
    let avgHeartRateBpm: Int  // 158
}

enum MatchResult: String, Hashable {
    case win = "승"
    case draw = "무"
    case lose = "패"
}

// MARK: - 라벨링 큐 (Apple Watch 자동 감지된 미확정 경기)

struct LabelingQueueItem: Identifiable, Hashable {
    let id = UUID()
    let date: String          // "2026-05-21 (수)"
    let time: String          // "09:00 ~ 11:20"
    let detectedQuarters: Int // 4 — Q1·Q2·Q3·Q4
}

// MARK: - Sample data (와이어프레임의 matches.jsx 하드코딩 값 그대로)

extension SampleMatch {
    static let samples: [SampleMatch] = [
        .init(dateNum: "5/18", dow: "수", opponent: "FC블루스",
              venue: "마포 풋살장", result: .win, score: "4-2",
              distanceKm: 3.2, avgSpeedKmh: 19.4, sprintCount: 14, avgHeartRateBpm: 158),
        .init(dateNum: "5/11", dow: "일", opponent: "레전드FC",
              venue: "양화 한강", result: .draw, score: "2-2",
              distanceKm: 2.8, avgSpeedKmh: 17.1, sprintCount: 9, avgHeartRateBpm: 162),
        .init(dateNum: "5/4", dow: "일", opponent: "어반FC",
              venue: "마포 풋살장", result: .lose, score: "1-3",
              distanceKm: 3.4, avgSpeedKmh: 18.0, sprintCount: 11, avgHeartRateBpm: 168),
        .init(dateNum: "4/27", dow: "일", opponent: "옆동네FC",
              venue: "○○공원 운동장", result: .win, score: "3-1",
              distanceKm: 3.0, avgSpeedKmh: 18.6, sprintCount: 12, avgHeartRateBpm: 156),
        .init(dateNum: "4/20", dow: "일", opponent: "한강조축",
              venue: "양화 한강", result: .win, score: "5-3",
              distanceKm: 3.7, avgSpeedKmh: 20.2, sprintCount: 16, avgHeartRateBpm: 161),
    ]
}

extension LabelingQueueItem {
    static let samples: [LabelingQueueItem] = [
        .init(date: "2026-05-21 (수)", time: "09:00 ~ 11:20", detectedQuarters: 4),
        .init(date: "2026-05-14 (수)", time: "06:30 ~ 08:40", detectedQuarters: 4),
    ]
}
