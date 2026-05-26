import Foundation

// api-spec.md §4 Invitations — Response DTO. Request 는 본문 없음 (POST {}).

struct InvitationResponse: Decodable, Hashable, Identifiable {
    let id: Int64
    let token: String
    let url: String
    let expiresAt: Date
    let useCount: Int
}

struct InvitationListResponse: Decodable {
    let invitations: [InvitationResponse]
}

struct InvitationPreviewResponse: Decodable, Hashable {
    let token: String
    let inviter: InvitationUser
    let expiresAt: Date
    let valid: Bool
}

struct InvitationUser: Decodable, Hashable {
    let id: Int64
    let displayName: String
}
