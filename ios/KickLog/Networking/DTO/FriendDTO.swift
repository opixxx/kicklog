import Foundation

// api-spec.md §3 Friends + §2.5 Users 검색 — Request/Response DTO.

// MARK: - 공통

struct FriendshipUser: Decodable, Hashable {
    let id: Int64
    let displayName: String
}

// MARK: - GET /friendships (3.1)

struct FriendshipResponse: Decodable, Hashable {
    let friendshipId: Int64
    let user: FriendshipUser
    let acceptedAt: Date
}

struct FriendshipListResponse: Decodable {
    let friends: [FriendshipResponse]
}

// MARK: - GET /friendships/pending (3.2)

struct PendingRequestResponse: Decodable, Hashable {
    let friendshipId: Int64
    let from: FriendshipUser
    let createdAt: Date
}

struct PendingRequestListResponse: Decodable {
    let requests: [PendingRequestResponse]
}

// MARK: - POST /friendships (3.3)

// token 또는 targetUserId 정확히 하나 — 서버에서 검증, 둘 다/둘 다 없음 → 400 FRIEND_INVALID_REQUEST.
struct CreateFriendshipRequest: Encodable {
    let token: String?
    let targetUserId: Int64?

    static func byUserId(_ userId: Int64) -> CreateFriendshipRequest {
        CreateFriendshipRequest(token: nil, targetUserId: userId)
    }

    static func byToken(_ token: String) -> CreateFriendshipRequest {
        CreateFriendshipRequest(token: token, targetUserId: nil)
    }
}

struct CreateFriendshipResponse: Decodable {
    let friendshipId: Int64
    let status: String         // "pending" | "accepted" (상대가 이미 보낸 요청이면 ON CONFLICT 로 자동 수락)
    let initiatedByMe: Bool
}

// MARK: - PATCH /friendships/{id} (3.4) — 수락

struct PatchFriendshipRequest: Encodable {
    let action: String         // "accept"

    static let accept = PatchFriendshipRequest(action: "accept")
}

struct PatchFriendshipResponse: Decodable {
    let friendshipId: Int64
    let status: String         // "accepted"
    let acceptedAt: Date
}

// MARK: - GET /users/search (2.5) — 친구 추가 시트 보조

struct UserSearchItem: Decodable, Hashable {
    let id: Int64
    let displayName: String
}

struct UserSearchResponse: Decodable {
    let users: [UserSearchItem]
}
