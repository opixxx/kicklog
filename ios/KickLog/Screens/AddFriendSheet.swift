import SwiftUI

// 친구 추가 시트 — §2.5 GET /users/search 로 검색 후 §3.3 POST /friendships 로 요청.
// 검색 입력은 400ms 디바운스. 항목 탭하면 즉시 요청 전송, 성공/이미 친구 등 결과를 inline 표시.
// (P1 V12/V13 — 닉네임 unique + 초대 링크 도메인 폐기. 닉네임 검색만이 친구 추가 경로.)
struct AddFriendSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var query: String = ""
    @State private var results: [UserSearchItem] = []
    @State private var isSearching = false
    @State private var pendingUserId: Int64?
    @State private var statusMessage: StatusMessage?
    @State private var searchTask: Task<Void, Never>?

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
            emptyHint
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

    private var emptyHint: some View {
        VStack(spacing: 10) {
            Spacer()
            KLIcon(name: "magnifyingglass.circle", size: 36, color: KLTokens.textTer)
            Text("닉네임으로 친구를 찾아보세요")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(KLTokens.text)
            Text("정확한 닉네임 또는 일부만 입력해도 검색됩니다")
                .font(.system(size: 12))
                .foregroundStyle(KLTokens.textSec)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity)
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
            statusMessage = StatusMessage(text: error.userMessage, isError: true)
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
            statusMessage = StatusMessage(text: error.userMessage, isError: true)
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
