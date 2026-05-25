import Foundation

// ADR-0004 D9 — 시즌 통계는 백엔드에서 derive. iOS 는 매번 fetch (캐시 없음, 오프라인 시 표시 불가).
@MainActor
final class SeasonStatService {
    static let shared = SeasonStatService()

    private let apiClient: any APIClient = URLSessionAPIClient()

    func fetchMine(year: Int) async throws -> SeasonStatResponse {
        try await apiClient.get("/users/me/seasons/\(year)", query: nil)
    }

    func fetchFriend(userId: Int64, year: Int) async throws -> SeasonStatResponse {
        try await apiClient.get("/users/\(userId)/seasons/\(year)", query: nil)
    }
}
