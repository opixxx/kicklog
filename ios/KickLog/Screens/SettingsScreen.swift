import SwiftUI
import SwiftData

// 설정 탭 — Form 스타일 리스트.
// JSX settings.jsx + SwiftData User 실데이터.
struct SettingsScreen: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding: Bool = false

    // 본인 User — SwiftData (AuthService 가 로그인 시 UPSERT 한 결과). 1단말 MVP 라 first 만.
    @Query private var users: [User]
    private var me: User? { users.first }

    // 동기화 대기 — 라벨링 완료(labeledAt != nil) but 아직 백엔드 PUT 못 한 매치 (syncedAt == nil)
    @Query(filter: #Predicate<Match> { $0.labeledAt != nil && $0.syncedAt == nil })
    private var pendingSyncMatches: [Match]

    @State private var hideHeartRate: Bool = false
    @State private var displayNameDraft: String = ""
    @State private var isShowingNameEditor: Bool = false
    @State private var isUpdatingProfile: Bool = false
    @State private var isDeletingAccount: Bool = false
    @State private var showDeleteConfirmation: Bool = false
    @State private var settingsErrorMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                KLNavBar(title: "설정")
                profileCard
                profileSection
                visibilitySection
                venueSection
                dataSection
                accountSection
                infoSection
                footer
            }
        }
        .background(KLTokens.bg)
        .toolbarVisibility(.hidden, for: .navigationBar)
        .onAppear {
            hideHeartRate = me?.hideHeartRate ?? false
        }
        .task { await refreshMe() }
        .onChange(of: me?.hideHeartRate) { _, newValue in
            hideHeartRate = newValue ?? false
        }
        .alert("오류", isPresented: Binding(
            get: { settingsErrorMessage != nil },
            set: { if !$0 { settingsErrorMessage = nil } }
        )) {
            Button("확인", role: .cancel) { settingsErrorMessage = nil }
        } message: {
            Text(settingsErrorMessage ?? "")
        }
        .alert("계정을 삭제할까요?", isPresented: $showDeleteConfirmation) {
            Button("취소", role: .cancel) {}
            Button("삭제", role: .destructive) { handleDeleteAccount() }
        } message: {
            Text("30일 안에 다시 로그인하면 복구할 수 있습니다.")
        }
        .sheet(isPresented: $isShowingNameEditor) {
            displayNameEditor
        }
    }

    // MARK: - Profile 카드 (상단)

    private var profileCard: some View {
        HStack(spacing: 14) {
            KLAvatar(name: me?.displayName ?? "?", size: 56)
            VStack(alignment: .leading, spacing: 2) {
                Text(me?.displayName ?? "—")
                    .font(.system(size: 20, weight: .bold))
                    .tracking(-0.4)
                    .foregroundStyle(KLTokens.text)
                Text(joinDateLabel)
                    .font(.system(size: 13))
                    .foregroundStyle(KLTokens.textSec)
            }
            Spacer(minLength: 0)
            KLIcon(name: "chevron.right", size: 14, color: KLTokens.textTer)
        }
        .klCard(padding: 16)
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .padding(.bottom, 8)
    }

    private var joinDateLabel: String {
        guard let createdAt = me?.createdAt else { return "—" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "yyyy년 M월부터 함께"
        return formatter.string(from: createdAt)
    }

    // MARK: - 섹션들

    private var profileSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            KLSettingsHeader(text: "프로필")
            KLSettingsGroup {
                Button(action: showDisplayNameEditor) {
                    KLSettingsRow(label: "이름", value: me?.displayName ?? "—")
                }
                .buttonStyle(.plain)
                KLSettingsRow(label: "이메일", chevron: false, value: me?.email ?? "—")
                KLSettingsRow(label: "가입일", chevron: false, isLast: true,
                              value: profileJoinDate)
            }
        }
    }

    private var profileJoinDate: String {
        guard let createdAt = me?.createdAt else { return "—" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "ko_KR")
        f.dateFormat = "yyyy년 M월 d일"
        return f.string(from: createdAt)
    }

    private var visibilitySection: some View {
        VStack(alignment: .leading, spacing: 0) {
            KLSettingsHeader(text: "공개 설정")
            KLSettingsGroup {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("친구에게 심박수 숨기기")
                            .font(.system(size: 16))
                            .tracking(-0.3)
                            .foregroundStyle(KLTokens.text)
                        Text("켜면 친구가 내 평균/최고 심박수를 볼 수 없습니다")
                            .font(.system(size: 12))
                            .lineSpacing(2)
                            .foregroundStyle(KLTokens.textSec)
                    }
                    Spacer(minLength: 0)
                    Toggle("", isOn: Binding(
                        get: { me?.hideHeartRate ?? hideHeartRate },
                        set: { updateHideHeartRate($0) }
                    ))
                        .labelsHidden()
                        .tint(KLTokens.pitch)
                        .disabled(me == nil || isUpdatingProfile)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 11)
            }
        }
    }

    private var venueSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            KLSettingsHeader(text: "운동장")
            KLSettingsGroup {
                KLSettingsRow(label: "내 운동장 관리", isLast: true, value: "3")
            }
        }
    }

    private var dataSection: some View {
        let pendingCount = pendingSyncMatches.count
        return VStack(alignment: .leading, spacing: 0) {
            KLSettingsHeader(text: "데이터")
            KLSettingsGroup {
                if pendingCount > 0 {
                    KLSettingsRow(
                        labelOnly: "동기화 대기",
                        sub: "네트워크가 안정되면 자동으로 재시도합니다",
                        badge: "\(pendingCount)건",
                        isLast: true
                    )
                } else {
                    KLSettingsRow(
                        labelOnly: "모두 동기화됨",
                        sub: "백엔드와 정합 상태입니다",
                        chevron: false,
                        isLast: true
                    )
                }
            }
        }
    }

    private var accountSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            KLSettingsHeader(text: "계정")
            KLSettingsGroup {
                Button(action: handleCurrentDeviceLogout) {
                    KLSettingsRow(labelOnly: "로그아웃", chevron: false)
                }
                .buttonStyle(.plain)
                Button(action: handleAllDevicesLogout) {
                    KLSettingsRow(labelOnly: "모든 기기에서 로그아웃", chevron: false)
                }
                .buttonStyle(.plain)
                Button(action: { showDeleteConfirmation = true }) {
                    KLSettingsRow(labelOnly: isDeletingAccount ? "계정 삭제 중" : "계정 삭제",
                                  sub: "30일 안에 다시 로그인하면 복구됩니다",
                                  chevron: false, destructive: true, isLast: true)
                }
                .buttonStyle(.plain)
                .disabled(isDeletingAccount)
            }
        }
    }

    private func handleCurrentDeviceLogout() {
        Task {
            await AuthService.shared.logoutCurrentDevice()
            clearLocalSession()
        }
    }

    private func handleAllDevicesLogout() {
        Task {
            await AuthService.shared.logoutAllDevices()
            clearLocalSession()
        }
    }

    private func clearLocalSession() {
        // 로컬 User 도 정리 + onboarding 재진입
        for u in users { modelContext.delete(u) }
        try? modelContext.save()
        hasCompletedOnboarding = false
    }

    private var displayNameEditor: some View {
        NavigationStack {
            Form {
                TextField("이름", text: $displayNameDraft)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
            .navigationTitle("이름 수정")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { isShowingNameEditor = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("저장") { saveDisplayName() }
                        .disabled(!canSaveDisplayName || isUpdatingProfile)
                }
            }
        }
        .presentationDetents([.height(180)])
    }

    private var canSaveDisplayName: Bool {
        let trimmed = displayNameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed.count <= 50 && trimmed != me?.displayName
    }

    private func refreshMe() async {
        do {
            let user = try await UserService.shared.fetchMe(into: modelContext)
            hideHeartRate = user.hideHeartRate
        } catch {
            settingsErrorMessage = error.localizedDescription
        }
    }

    private func showDisplayNameEditor() {
        displayNameDraft = me?.displayName ?? ""
        isShowingNameEditor = true
    }

    private func saveDisplayName() {
        let newDisplayName = displayNameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !newDisplayName.isEmpty, newDisplayName.count <= 50 else { return }

        Task { @MainActor in
            isUpdatingProfile = true
            defer { isUpdatingProfile = false }
            do {
                _ = try await UserService.shared.updateMe(
                    displayName: newDisplayName,
                    into: modelContext
                )
                isShowingNameEditor = false
            } catch {
                settingsErrorMessage = error.localizedDescription
            }
        }
    }

    private func updateHideHeartRate(_ newValue: Bool) {
        guard let user = me else { return }
        let previousValue = user.hideHeartRate
        guard previousValue != newValue else { return }

        hideHeartRate = newValue
        user.hideHeartRate = newValue
        try? modelContext.save()

        Task { @MainActor in
            isUpdatingProfile = true
            defer { isUpdatingProfile = false }
            do {
                _ = try await UserService.shared.updateMe(
                    hideHeartRate: newValue,
                    into: modelContext
                )
            } catch {
                hideHeartRate = previousValue
                user.hideHeartRate = previousValue
                try? modelContext.save()
                settingsErrorMessage = error.localizedDescription
            }
        }
    }

    private func handleDeleteAccount() {
        guard !isDeletingAccount else { return }

        Task { @MainActor in
            isDeletingAccount = true
            defer { isDeletingAccount = false }
            do {
                try await UserService.shared.deleteMe()
                AuthTokenStore.shared.clear()
                clearLocalSession()
            } catch {
                settingsErrorMessage = error.localizedDescription
            }
        }
    }

    private var infoSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            KLSettingsHeader(text: "정보")
            KLSettingsGroup {
                KLSettingsRow(label: "버전", chevron: false, value: "1.0.0")
                KLSettingsRow(labelOnly: "오픈소스 라이선스")
                KLSettingsRow(labelOnly: "개인정보 처리방침")
                KLSettingsRow(labelOnly: "이용약관", isLast: true)
            }
        }
    }

    private var footer: some View {
        Text("KickLog by opixxx")
            .font(.system(size: 12, weight: .medium))
            .tracking(-0.1)
            .foregroundStyle(KLTokens.textTer)
            .frame(maxWidth: .infinity)
            .padding(.top, 24)
            .padding(.bottom, 12)
    }
}

#Preview {
    NavigationStack { SettingsScreen() }
}
