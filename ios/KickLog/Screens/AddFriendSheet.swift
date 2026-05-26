import SwiftUI

// 친구 추가 시트 — §2.5 GET /users/search 로 검색 후 §3.3 POST /friendships 로 요청.
// 검색 입력은 0.4s 디바운스. 항목 탭하면 즉시 요청 전송, 성공/이미 친구 등 결과를 inline 표시.
// 검색 입력이 비어있을 때 placeholder 자리에 §4 Invitations 섹션을 노출
// (활성 링크 목록 + 발급/공유/폐기). 발급 시 시스템 공유 시트 자동 표시.
struct AddFriendSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var query: String = ""
    @State private var results: [UserSearchItem] = []
    @State private var isSearching = false
    @State private var pendingUserId: Int64?
    @State private var statusMessage: StatusMessage?
    @State private var searchTask: Task<Void, Never>?

    // Invitations
    @State private var invitations: [InvitationResponse] = []
    @State private var isLoadingInvitations = false
    @State private var isCreatingInvitation = false
    @State private var revokingInvitationId: Int64?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                searchField
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 8)

                if let status = statusMessage {
                    statusBanner(status)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 8)
                }

                resultsList
            }
            .background(KLTokens.bg)
            .navigationTitle("친구 추가")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { dismiss() }
                }
            }
            .task { await loadInvitations() }
        }
    }

    // MARK: - 검색 입력

    private var searchField: some View {
        HStack(spacing: 8) {
            KLIcon(name: "magnifyingglass", size: 16, color: KLTokens.textSec)
            TextField("닉네임으로 검색", text: $query)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .onChange(of: query) { _, newValue in
                    scheduleSearch(for: newValue)
                }
            if !query.isEmpty {
                Button(action: { query = ""; results = []; statusMessage = nil }) {
                    KLIcon(name: "xmark.circle.fill", size: 16, color: KLTokens.textTer)
                }
                .buttonStyle(.plain)
            }
            if isSearching {
                ProgressView().scaleEffect(0.8)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(KLTokens.chipBg, in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - 결과 리스트

    @ViewBuilder
    private var resultsList: some View {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            // 검색 전 — 초대 링크 섹션 노출
            ScrollView { invitationSection }
                .refreshable { await loadInvitations() }
        } else if results.isEmpty && !isSearching {
            placeholderView(text: "검색 결과가 없습니다")
        } else {
            List(results) { item in
                userRow(item)
                    .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                    .listRowBackground(KLTokens.bg)
            }
            .listStyle(.plain)
        }
    }

    private func placeholderView(text: String) -> some View {
        VStack {
            Spacer()
            Text(text)
                .font(.system(size: 14))
                .foregroundStyle(KLTokens.textSec)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private func userRow(_ item: UserSearchItem) -> some View {
        let inFlight = pendingUserId == item.id
        return Button(action: { Task { await sendRequest(to: item) } }) {
            HStack(spacing: 12) {
                KLAvatar(name: item.displayName)
                Text(item.displayName)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(KLTokens.text)
                Spacer()
                if inFlight {
                    ProgressView().scaleEffect(0.8)
                } else {
                    Text("요청")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(KLTokens.pitch, in: Capsule())
                }
            }
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(inFlight)
    }

    private func statusBanner(_ status: StatusMessage) -> some View {
        Text(status.text)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(status.isError ? KLTokens.loseFg : KLTokens.winFg)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                (status.isError ? KLTokens.loseBg : KLTokens.winBg),
                in: RoundedRectangle(cornerRadius: 9)
            )
    }

    // MARK: - 초대 링크 섹션 (§4)

    private var invitationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("초대 링크")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(KLTokens.textSec)
                Spacer()
                if isLoadingInvitations {
                    ProgressView().scaleEffect(0.7)
                }
            }
            .padding(.horizontal, 4)

            Text("닉네임을 모를 때, 링크로 초대해 친구를 추가할 수 있어요. 만료까지 15일.")
                .font(.system(size: 12))
                .foregroundStyle(KLTokens.textSec)
                .padding(.horizontal, 4)
                .padding(.bottom, 4)

            createInvitationButton

            if !invitations.isEmpty {
                VStack(spacing: 10) {
                    ForEach(invitations) { invitation in
                        invitationCard(invitation)
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 24)
    }

    private var createInvitationButton: some View {
        Button(action: { Task { await createInvitation() } }) {
            HStack(spacing: 8) {
                if isCreatingInvitation {
                    ProgressView().tint(.white)
                } else {
                    KLIcon(name: "link.badge.plus", size: 18, color: .white)
                    Text("새 초대 링크 만들기")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 46)
            .background(KLTokens.pitch, in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .disabled(isCreatingInvitation)
    }

    private func invitationCard(_ invitation: InvitationResponse) -> some View {
        let isRevoking = revokingInvitationId == invitation.id
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(invitation.url)
                    .font(.system(size: 13, weight: .medium).monospaced())
                    .foregroundStyle(KLTokens.text)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 8)
                Text(useCountLabel(invitation.useCount))
                    .font(.system(size: 11, weight: .semibold).monospacedDigit())
                    .foregroundStyle(KLTokens.textSec)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(KLTokens.chipBg, in: Capsule())
            }

            HStack(spacing: 4) {
                KLIcon(name: "clock", size: 11, color: KLTokens.textTer)
                Text(expiresLabel(invitation.expiresAt))
                    .font(.system(size: 12).monospacedDigit())
                    .foregroundStyle(KLTokens.textSec)
            }

            HStack(spacing: 8) {
                Button(action: { copyToClipboard(invitation.url) }) {
                    invitationActionLabel(icon: "doc.on.doc", text: "복사")
                }
                .buttonStyle(.plain)

                ShareLink(item: URL(string: invitation.url) ?? URL(string: "https://kicklog.app")!) {
                    invitationActionLabel(icon: "square.and.arrow.up", text: "공유")
                }
                .buttonStyle(.plain)

                Button(role: .destructive, action: { Task { await revoke(invitation) } }) {
                    invitationActionLabel(
                        icon: "trash",
                        text: isRevoking ? "폐기 중..." : "폐기",
                        destructive: true
                    )
                }
                .buttonStyle(.plain)
                .disabled(isRevoking)
            }
        }
        .padding(14)
        .background(KLTokens.bgElev, in: RoundedRectangle(cornerRadius: KLTokens.radiusCard))
    }

    private func invitationActionLabel(icon: String, text: String, destructive: Bool = false) -> some View {
        let fg = destructive ? KLTokens.loseFg : KLTokens.text
        let bg = destructive ? KLTokens.loseBg : KLTokens.chipBg
        return HStack(spacing: 4) {
            KLIcon(name: icon, size: 12, color: fg)
            Text(text)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(fg)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(bg, in: RoundedRectangle(cornerRadius: 9))
    }

    private func useCountLabel(_ count: Int) -> String { "사용 \(count)회" }

    private func expiresLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "M월 d일 HH:mm"
        return "\(formatter.string(from: date)) 만료"
    }

    private func copyToClipboard(_ value: String) {
        UIPasteboard.general.string = value
        statusMessage = StatusMessage(text: "링크가 복사되었습니다", isError: false)
    }

    // MARK: - 검색 / 요청

    private func scheduleSearch(for raw: String) {
        searchTask?.cancel()
        statusMessage = nil
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            results = []
            isSearching = false
            return
        }
        isSearching = true
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(400))
            if Task.isCancelled { return }
            await runSearch(trimmed)
        }
    }

    private func runSearch(_ q: String) async {
        defer { isSearching = false }
        do {
            let response = try await FriendService.shared.searchUsers(query: q)
            if Task.isCancelled { return }
            results = response.users
        } catch {
            if Task.isCancelled { return }
            results = []
            statusMessage = StatusMessage(text: friendlyMessage(error), isError: true)
        }
    }

    private func sendRequest(to item: UserSearchItem) async {
        guard pendingUserId == nil else { return }
        pendingUserId = item.id
        defer { pendingUserId = nil }
        do {
            let response = try await FriendService.shared.createFriendship(targetUserId: item.id)
            let label = response.status == "accepted"
                ? "\(item.displayName) 님과 친구가 되었습니다"
                : "\(item.displayName) 님에게 친구 요청을 보냈습니다"
            statusMessage = StatusMessage(text: label, isError: false)
        } catch {
            statusMessage = StatusMessage(text: friendlyMessage(error), isError: true)
        }
    }

    // MARK: - Invitation API

    private func loadInvitations() async {
        isLoadingInvitations = true
        defer { isLoadingInvitations = false }
        do {
            let response = try await InvitationService.shared.fetchActiveInvitations()
            invitations = response.invitations.sorted { $0.expiresAt > $1.expiresAt }
        } catch {
            statusMessage = StatusMessage(text: friendlyMessage(error), isError: true)
        }
    }

    private func createInvitation() async {
        guard !isCreatingInvitation else { return }
        isCreatingInvitation = true
        defer { isCreatingInvitation = false }
        do {
            let new = try await InvitationService.shared.createInvitation()
            invitations.insert(new, at: 0)
            UIPasteboard.general.string = new.url
            statusMessage = StatusMessage(text: "초대 링크가 발급되어 복사되었습니다", isError: false)
        } catch {
            statusMessage = StatusMessage(text: friendlyMessage(error), isError: true)
        }
    }

    private func revoke(_ invitation: InvitationResponse) async {
        guard revokingInvitationId == nil else { return }
        revokingInvitationId = invitation.id
        defer { revokingInvitationId = nil }
        do {
            try await InvitationService.shared.revokeInvitation(id: invitation.id)
            invitations.removeAll { $0.id == invitation.id }
            statusMessage = StatusMessage(text: "초대 링크를 폐기했습니다", isError: false)
        } catch {
            statusMessage = StatusMessage(text: friendlyMessage(error), isError: true)
        }
    }

    private func friendlyMessage(_ error: Error) -> String {
        guard let apiError = error as? APIError else { return error.localizedDescription }
        switch apiError {
        case .noConnection: return "네트워크 연결을 확인해 주세요"
        case .unauthorized: return "로그인이 만료되었습니다"
        case .server(_, let body, _):
            // FRIEND_ALREADY_EXISTS / FRIEND_SELF_REQUEST / INVITATION_* 등 백엔드 메시지 그대로 노출.
            return body?.message ?? "서버 오류가 발생했습니다"
        case .decodingFailed: return "응답을 처리하지 못했습니다"
        case .unknown: return "알 수 없는 오류가 발생했습니다"
        }
    }

    private struct StatusMessage: Equatable {
        let text: String
        let isError: Bool
    }
}

#Preview {
    AddFriendSheet()
}
