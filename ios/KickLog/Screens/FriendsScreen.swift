import SwiftUI

// 친구 탭 — 백엔드 API 실연동 (E4).
// §3.1 GET /friendships · §3.2 GET /friendships/pending · §3.4 PATCH(수락) · §3.5 DELETE(거절)
struct FriendsScreen: View {
    @Environment(\.colorScheme) private var scheme

    @State private var friends: [FriendSummary] = []
    @State private var pendingRequests: [PendingFriendRequest] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showingAddSheet = false
    @State private var actioningRequestId: Int64?
    // 친구 목록 클라이언트 필터 — 백엔드 검색 X (이미 받은 목록에서 displayName 부분 일치).
    @State private var searchQuery: String = ""

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.locale = Locale(identifier: "ko_KR")
        f.unitsStyle = .full
        return f
    }()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                KLNavBar(title: "친구")

                KLSearchBar(placeholder: "친구 검색 (이름)", text: $searchQuery) {
                    Button(action: { showingAddSheet = true }) {
                        ZStack {
                            Circle().fill(KLTokens.pitch)
                                .frame(width: 38, height: 38)
                            KLIcon(name: "plus", size: 20, color: .white)
                        }
                    }
                    .buttonStyle(.plain)
                }

                content
                Color.clear.frame(height: 16)
            }
        }
        .background(KLTokens.bg)
        .toolbarVisibility(.hidden, for: .navigationBar)
        .navigationDestination(for: FriendSummary.self) { friend in
            FriendDetailScreen(friend: friend)
        }
        .sheet(isPresented: $showingAddSheet, onDismiss: { Task { await load() } }) {
            AddFriendSheet()
        }
        .task { await load() }
        // .refreshable 클로저는 view rebuild 시 내부 Task 가 자동 cancel 되어
        // URLSession 요청이 -999 cancelled 로 끊긴다. 새 Task 로 wrapping 해 lifetime 분리.
        .refreshable { _ = await Task { await load() }.value }
    }

    // MARK: - 본문 분기

    @ViewBuilder
    private var content: some View {
        if isLoading && friends.isEmpty && pendingRequests.isEmpty {
            ProgressView()
                .frame(maxWidth: .infinity, minHeight: 200)
        } else if let errorMessage, friends.isEmpty && pendingRequests.isEmpty {
            errorView(errorMessage)
        } else {
            if !pendingRequests.isEmpty {
                sectionLabel("친구 요청 · 대기 중 \(pendingRequests.count)")
                VStack(spacing: 12) {
                    ForEach(pendingRequests) { request in
                        pendingCard(request)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }

            friendsListSection
        }
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 12) {
            Text(message)
                .font(.system(size: 14))
                .foregroundStyle(KLTokens.textSec)
                .multilineTextAlignment(.center)
            Button("다시 시도") { Task { await load() } }
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(KLTokens.pitch)
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, minHeight: 200)
    }

    // MARK: - Pending 요청 카드

    private func pendingCard(_ request: PendingFriendRequest) -> some View {
        let inFlight = actioningRequestId == request.id
        return VStack(spacing: 12) {
            HStack(spacing: 12) {
                KLAvatar(name: request.displayName)
                VStack(alignment: .leading, spacing: 2) {
                    Text(request.displayName)
                        .font(.system(size: 16, weight: .semibold))
                        .tracking(-0.3)
                        .foregroundStyle(KLTokens.text)
                    Text(relativeLabel(from: request.createdAt) + " 요청")
                        .font(.system(size: 13))
                        .foregroundStyle(KLTokens.textSec)
                }
                Spacer(minLength: 0)
            }
            GeometryReader { proxy in
                HStack(spacing: 8) {
                    Button(action: { Task { await accept(request) } }) {
                        Text(inFlight ? "처리 중..." : "수락")
                            .font(.system(size: 14, weight: .bold))
                            .tracking(-0.2)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 36)
                            .background(KLTokens.pitch, in: RoundedRectangle(cornerRadius: 9))
                    }
                    .buttonStyle(.plain)
                    .disabled(inFlight)
                    .frame(width: (proxy.size.width - 8) * 0.58)

                    Button(action: { Task { await reject(request) } }) {
                        Text("거절")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(KLTokens.text)
                            .frame(maxWidth: .infinity)
                            .frame(height: 36)
                            .background(KLTokens.chipBg, in: RoundedRectangle(cornerRadius: 9))
                    }
                    .buttonStyle(.plain)
                    .disabled(inFlight)
                }
            }
            .frame(height: 36)
        }
        .klCard(padding: 14)
    }

    // MARK: - 친구 리스트

    // 검색어 비어있으면 전체. 비어있지 않으면 displayName 부분 일치 (대소문자 무시 + 공백 trim).
    private var filteredFriends: [FriendSummary] {
        let q = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return friends }
        return friends.filter { $0.displayName.localizedCaseInsensitiveContains(q) }
    }

    private var friendsListSection: some View {
        let visible = filteredFriends
        return VStack(alignment: .leading, spacing: 0) {
            (Text("내 친구 · ") + Text("\(visible.count)").monospacedDigit())
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(KLTokens.textSec)
                .padding(.horizontal, 20)
                .padding(.bottom, 6)

            if friends.isEmpty {
                emptyFriendsState
            } else if visible.isEmpty {
                noMatchState
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(visible.enumerated()), id: \.element.id) { index, friend in
                        NavigationLink(value: friend) {
                            friendRow(friend, isLast: index == visible.count - 1)
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
    }

    private var noMatchState: some View {
        VStack(spacing: 6) {
            Text("일치하는 친구가 없어요")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(KLTokens.text)
            Text("이름 일부를 다시 입력해 보세요")
                .font(.system(size: 12))
                .foregroundStyle(KLTokens.textSec)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .background(KLTokens.bgElev, in: RoundedRectangle(cornerRadius: KLTokens.radiusCard))
        .padding(.horizontal, 16)
    }

    private var emptyFriendsState: some View {
        VStack(spacing: 8) {
            Text("아직 친구가 없습니다")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(KLTokens.text)
            Text("우측 상단 + 버튼으로 친구를 추가해 보세요")
                .font(.system(size: 13))
                .foregroundStyle(KLTokens.textSec)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .background(KLTokens.bgElev, in: RoundedRectangle(cornerRadius: KLTokens.radiusCard))
        .padding(.horizontal, 16)
    }

    private func friendRow(_ friend: FriendSummary, isLast: Bool) -> some View {
        HStack(spacing: 12) {
            KLAvatar(name: friend.displayName)
            VStack(alignment: .leading, spacing: 2) {
                Text(friend.displayName)
                    .font(.system(size: 16, weight: .semibold))
                    .tracking(-0.3)
                    .foregroundStyle(KLTokens.text)
                Text(acceptedLabel(from: friend.acceptedAt))
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
                    .padding(.leading, 68)
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

    // MARK: - 라벨 변환

    private func relativeLabel(from date: Date) -> String {
        Self.relativeFormatter.localizedString(for: date, relativeTo: Date())
    }

    private func acceptedLabel(from date: Date) -> String {
        "친구된 지 " + Self.relativeFormatter.localizedString(for: date, relativeTo: Date())
            .replacingOccurrences(of: " 전", with: "")
    }

    // MARK: - 데이터 로드 / 액션

    private func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            async let friendsTask = FriendService.shared.fetchFriends()
            async let pendingTask = FriendService.shared.fetchPendingRequests()
            let (friendsResp, pendingResp) = try await (friendsTask, pendingTask)
            friends = friendsResp.friends.map(FriendSummary.init(from:))
            pendingRequests = pendingResp.requests.map(PendingFriendRequest.init(from:))
        } catch {
            errorMessage = friendlyMessage(error)
        }
    }

    private func accept(_ request: PendingFriendRequest) async {
        guard actioningRequestId == nil else { return }
        actioningRequestId = request.id
        defer { actioningRequestId = nil }
        do {
            let response = try await FriendService.shared.acceptFriendship(id: request.id)
            pendingRequests.removeAll { $0.id == request.id }
            friends.insert(
                FriendSummary(
                    id: response.friendshipId,
                    userId: request.fromUserId,
                    displayName: request.displayName,
                    acceptedAt: response.acceptedAt
                ),
                at: 0
            )
        } catch {
            errorMessage = friendlyMessage(error)
        }
    }

    private func reject(_ request: PendingFriendRequest) async {
        guard actioningRequestId == nil else { return }
        actioningRequestId = request.id
        defer { actioningRequestId = nil }
        do {
            try await FriendService.shared.rejectOrRemoveFriendship(id: request.id)
            pendingRequests.removeAll { $0.id == request.id }
        } catch {
            errorMessage = friendlyMessage(error)
        }
    }

    private func friendlyMessage(_ error: Error) -> String {
        if let apiError = error as? APIError {
            switch apiError {
            case .noConnection: return "네트워크 연결을 확인해 주세요"
            case .unauthorized: return "로그인이 만료되었습니다"
            case .server(_, let body, _): return body?.message ?? "서버 오류가 발생했습니다"
            case .decodingFailed: return "응답을 처리하지 못했습니다"
            case .unknown: return "알 수 없는 오류가 발생했습니다"
            }
        }
        return error.localizedDescription
    }
}

#Preview {
    NavigationStack { FriendsScreen() }
}
