import Foundation

// api-spec.md §4 Invitations — 친구 초대 링크 API 클라이언트.
// 4.1 POST /invitations · 4.2 GET /invitations/{token} 🌐 · 4.3 GET /invitations · 4.4 DELETE /invitations/{id}
@MainActor
final class InvitationService {
    static let shared = InvitationService()

    private let apiClient: any APIClient = URLSessionAPIClient()

    // MARK: - 발급 (4.1)

    func createInvitation() async throws -> InvitationResponse {
        // POST 본문은 spec 상 비어있어도 무방하나, APIClient 의 post(_:) 오버로드를
        // 사용하기 위해 body 없는 변형을 호출한다.
        try await apiClient.post("/invitations")
    }

    // MARK: - 미리보기 (4.2, 인증 불필요)

    func preview(token: String) async throws -> InvitationPreviewResponse {
        try await apiClient.get("/invitations/\(token)", query: nil)
    }

    // MARK: - 활성 목록 (4.3)

    func fetchActiveInvitations() async throws -> InvitationListResponse {
        try await apiClient.get("/invitations", query: nil)
    }

    // MARK: - 폐기 (4.4)

    func revokeInvitation(id: Int64) async throws {
        let _: EmptyResponse = try await apiClient.delete("/invitations/\(id)")
    }
}
