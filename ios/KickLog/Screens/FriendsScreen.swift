import SwiftUI

// 친구 탭 — populated 변형.
// JSX friends.jsx 의 KLFriendsPopulatedScreen 1차 포팅 (empty 변형은 후속).
struct FriendsScreen: View {
    @Environment(\.colorScheme) private var scheme
    @State private var friends: [Friend] = Friend.samples
    @State private var pendingRequest: FriendRequest? = FriendRequest.pendingSample

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                KLNavBar(title: "친구")

                KLSearchBar(placeholder: "친구 검색 (이름)") {
                    Button(action: {}) {
                        ZStack {
                            Circle().fill(KLTokens.pitch)
                                .frame(width: 38, height: 38)
                            KLIcon(name: "plus", size: 20, color: .white)
                        }
                    }
                    .buttonStyle(.plain)
                }

                if let pendingRequest {
                    sectionLabel("친구 요청 · 대기 중")
                    pendingCard(pendingRequest)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 16)
                }

                friendsListSection
                Color.clear.frame(height: 16)
            }
        }
        .background(KLTokens.bg)
        .toolbarVisibility(.hidden, for: .navigationBar)
        .navigationDestination(for: Friend.self) { friend in
            FriendDetailScreen(friend: friend)
        }
    }

    // MARK: - Pending 요청 카드

    private func pendingCard(_ request: FriendRequest) -> some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                KLAvatar(name: request.name)
                VStack(alignment: .leading, spacing: 2) {
                    Text(request.name)
                        .font(.system(size: 16, weight: .semibold))
                        .tracking(-0.3)
                        .foregroundStyle(KLTokens.text)
                    Text(request.receivedLabel)
                        .font(.system(size: 13))
                        .foregroundStyle(KLTokens.textSec)
                }
                Spacer(minLength: 0)
            }
            GeometryReader { proxy in
                HStack(spacing: 8) {
                    Button(action: { pendingRequest = nil }) {
                        Text("수락")
                            .font(.system(size: 14, weight: .bold))
                            .tracking(-0.2)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 36)
                            .background(KLTokens.pitch, in: RoundedRectangle(cornerRadius: 9))
                    }
                    .buttonStyle(.plain)
                    .frame(width: (proxy.size.width - 8) * 0.58)

                    Button(action: { pendingRequest = nil }) {
                        Text("거절")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(KLTokens.text)
                            .frame(maxWidth: .infinity)
                            .frame(height: 36)
                            .background(KLTokens.chipBg, in: RoundedRectangle(cornerRadius: 9))
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(height: 36)
        }
        .klCard(padding: 14)
    }

    // MARK: - 친구 리스트

    private var friendsListSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            (Text("내 친구 · ") + Text("\(friends.count)").monospacedDigit())
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(KLTokens.textSec)
                .padding(.horizontal, 20)
                .padding(.bottom, 6)

            VStack(spacing: 0) {
                ForEach(Array(friends.enumerated()), id: \.element.id) { index, friend in
                    NavigationLink(value: friend) {
                        friendRow(friend, isLast: index == friends.count - 1)
                    }
                    .buttonStyle(.plain)
                }
            }
            .background(KLTokens.bgElev)
            .clipShape(RoundedRectangle(cornerRadius: KLTokens.radiusCard))
            .padding(.horizontal, 16)
            .klCardShadow(scheme)
        }
    }

    private func friendRow(_ friend: Friend, isLast: Bool) -> some View {
        HStack(spacing: 12) {
            KLAvatar(name: friend.name)
            VStack(alignment: .leading, spacing: 2) {
                Text(friend.name)
                    .font(.system(size: 16, weight: .semibold))
                    .tracking(-0.3)
                    .foregroundStyle(KLTokens.text)
                Text(friend.lastMatchLabel)
                    .font(.system(size: 13))
                    .foregroundStyle(KLTokens.textSec)
            }
            Spacer(minLength: 0)
            KLIcon(name: "chevron.right", size: 14, color: KLTokens.textTer)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(minHeight: 64)
        .overlay(alignment: .bottom) {
            if !isLast {
                Rectangle()
                    .fill(KLTokens.sep)
                    .frame(height: 0.5)
                    .padding(.leading, 68)  // avatar+spacing 만큼 들여쓰기
            }
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(KLTokens.textSec)
            .padding(.horizontal, 20)
            .padding(.bottom, 6)
    }
}

#Preview {
    NavigationStack { FriendsScreen() }
}
