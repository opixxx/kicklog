import Foundation

// api-spec.md §3 Friends + §2.5 Users 검색 — 친구 도메인 API 클라이언트.
// 거절은 spec 상 PATCH 가 아니라 DELETE /friendships/{id} (3.5: pending 거절/취소도 DELETE).
@MainActor
final class FriendService {
    static let shared = FriendService()

    private let apiClient: any APIClient = URLSessionAPIClient()

    // MARK: - 조회

    func fetchFriends() async throws -> FriendshipListResponse {
        try await apiClient.get("/friendships", query: nil)
    }

    func fetchPendingRequests() async throws -> PendingRequestListResponse {
        try await apiClient.get("/friendships/pending", query: nil)
    }

    // MARK: - 친구 추가

    func createFriendship(targetUserId: Int64) async throws -> CreateFriendshipResponse {
        try await apiClient.post("/friendships", body: CreateFriendshipRequest.byUserId(targetUserId))
    }

    // MARK: - 수락 / 거절

    func acceptFriendship(id: Int64) async throws -> PatchFriendshipResponse {
        try await apiClient.patch("/friendships/\(id)", body: PatchFriendshipRequest.accept)
    }

    // 거절(pending) · 친구 끊기(accepted) · 내가 보낸 요청 취소 — 모두 DELETE (3.5).
    func rejectOrRemoveFriendship(id: Int64) async throws {
        let _: EmptyResponse = try await apiClient.delete("/friendships/\(id)")
    }

    // MARK: - 사용자 검색 (친구 추가 시트 보조)

    func searchUsers(query: String, limit: Int = 20) async throws -> UserSearchResponse {
        let items: [URLQueryItem] = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "limit", value: String(limit))
        ]
        return try await apiClient.get("/users/search", query: items)
    }
}
