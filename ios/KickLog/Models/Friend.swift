import Foundation

// 친구 — 더미 단계 모델.
struct Friend: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let lastMatchLabel: String   // "최근 경기: 3일 전 · 95.4km"
}

extension Friend {
    static let samples: [Friend] = [
        .init(name: "김조축", lastMatchLabel: "최근 경기: 3일 전 · 95.4km"),
        .init(name: "이미드", lastMatchLabel: "최근 경기: 5일 전 · 78.2km"),
        .init(name: "박수비", lastMatchLabel: "최근 경기: 어제 · 102.6km"),
        .init(name: "최골키", lastMatchLabel: "최근 경기: 2주 전 · 41.0km"),
        .init(name: "정공격", lastMatchLabel: "최근 경기: 6일 전 · 88.1km"),
    ]
}

// 친구 요청 (대기 중)
struct FriendRequest: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let receivedLabel: String  // "어제 요청 보냄"
}

extension FriendRequest {
    static let pendingSample = FriendRequest(name: "박축구", receivedLabel: "어제 요청 보냄")
}
