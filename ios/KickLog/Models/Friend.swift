import Foundation

// 친구 도메인 모델 — 백엔드 §3 Friends 응답을 화면 단에서 다루기 쉽게 정규화.
// id = friendshipId (NavigationLink / ForEach 키로 사용).

struct Friend: Identifiable, Hashable {
    let id: Int64               // friendshipId
    let userId: Int64
    let displayName: String
    let acceptedAt: Date

    init(from response: FriendshipResponse) {
        self.id = response.friendshipId
        self.userId = response.user.id
        self.displayName = response.user.displayName
        self.acceptedAt = response.acceptedAt
    }

    init(id: Int64, userId: Int64, displayName: String, acceptedAt: Date) {
        self.id = id
        self.userId = userId
        self.displayName = displayName
        self.acceptedAt = acceptedAt
    }
}

struct PendingFriendRequest: Identifiable, Hashable {
    let id: Int64               // friendshipId
    let fromUserId: Int64
    let displayName: String
    let createdAt: Date

    init(from response: PendingRequestResponse) {
        self.id = response.friendshipId
        self.fromUserId = response.from.id
        self.displayName = response.from.displayName
        self.createdAt = response.createdAt
    }

    init(id: Int64, fromUserId: Int64, displayName: String, createdAt: Date) {
        self.id = id
        self.fromUserId = fromUserId
        self.displayName = displayName
        self.createdAt = createdAt
    }
}

// MARK: - Preview 용 샘플

extension Friend {
    static let previewSamples: [Friend] = [
        .init(id: 1, userId: 101, displayName: "김조축", acceptedAt: Date().addingTimeInterval(-86_400 * 30)),
        .init(id: 2, userId: 102, displayName: "이미드", acceptedAt: Date().addingTimeInterval(-86_400 * 14)),
        .init(id: 3, userId: 103, displayName: "박수비", acceptedAt: Date().addingTimeInterval(-86_400 * 7))
    ]
}

extension PendingFriendRequest {
    static let previewSample = PendingFriendRequest(
        id: 99, fromUserId: 999, displayName: "박축구", createdAt: Date().addingTimeInterval(-86_400)
    )
}
