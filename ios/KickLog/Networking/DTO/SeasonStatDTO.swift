import Foundation

// api-spec.md §8 — 시즌 통계 응답.
// ADR-0004 D9 — 백엔드 derive (iOS SwiftData reduce 안 함).
struct SeasonStatResponse: Decodable {
    let year: Int
    let totalDistanceM: Int
    let totalGoals: Int
    let totalAssists: Int
    let matchCount: Int
    let quarterCount: Int
    let best: SeasonBestResponse
}

struct SeasonBestResponse: Decodable {
    let maxSpeedKmh: Double
    let longestMatchDistanceM: Int
    let mostSprintCount: Int
}
