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

    // 내 운동장 — Settings "내 운동장 관리" 행 카운트 (서버 동기화된 venue 만, 로컬 임시 venue 제외)
    @Query(filter: #Predicate<Venue> { $0.serverId > 0 })
    private var myVenues: [Venue]

    @State private var displayNameDraft: String = ""
    @State private var isShowingNameEditor: Bool = false
    @State private var isUpdatingProfile: Bool = false
    @State private var isDeletingAccount: Bool = false
    @State private var showDeleteConfirmation: Bool = false
    @State private var settingsErrorMessage: String?
    #if DEBUG
    @State private var isSeedingWorkout: Bool = false
    @State private var debugInfoMessage: String?
    #endif

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                KLNavBar(title: "설정")
                profileCard
                profileSection
                venueSection
                dataSection
                #if DEBUG
                debugSection
                #endif
                accountSection
                infoSection
                footer
            }
        }
        .background(KLTokens.bg)
        .toolbarVisibility(.hidden, for: .navigationBar)
        .navigationDestination(for: VenueRoute.self) { route in
            switch route {
            case .list: VenueListScreen()
            }
        }
        .task { await refreshMe() }
        .alert("오류", isPresented: Binding(
            get: { settingsErrorMessage != nil },
            set: { if !$0 { settingsErrorMessage = nil } }
        )) {
            Button("확인", role: .cancel) { settingsErrorMessage = nil }
        } message: {
            Text(settingsErrorMessage ?? "")
        }
        #if DEBUG
        .alert("디버그", isPresented: Binding(
            get: { debugInfoMessage != nil },
            set: { if !$0 { debugInfoMessage = nil } }
        )) {
            Button("확인", role: .cancel) { debugInfoMessage = nil }
        } message: {
            Text(debugInfoMessage ?? "")
        }
        #endif
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

    private var venueSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            KLSettingsHeader(text: "운동장")
            KLSettingsGroup {
                NavigationLink(value: VenueRoute.list) {
                    KLSettingsRow(label: "내 운동장 관리", isLast: true,
                                  value: "\(myVenues.count)")
                }
                .buttonStyle(.plain)
            }
        }
    }

    // SettingsScreen 내부 NavigationStack 의 destination 라우트 식별자.
    // 운동장 목록만이라 단일 case지만, 향후 다른 진입점도 같은 방식으로 확장한다.
    enum VenueRoute: Hashable { case list }

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

    // MARK: - DEBUG 섹션 (개발 빌드 전용)

    #if DEBUG
    private var debugSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            KLSettingsHeader(text: "디버그 (개발 빌드)")
            KLSettingsGroup {
                Button(action: handleSeedTestWorkout) {
                    KLSettingsRow(
                        labelOnly: isSeedingWorkout ? "시드 중..." : "테스트 워크아웃 시드",
                        sub: "동일 GPS 근방 4쿼터 (≈75분) 임의 데이터 생성",
                        chevron: false,
                        isLast: true
                    )
                }
                .buttonStyle(.plain)
                .disabled(isSeedingWorkout)
            }
        }
    }

    private func handleSeedTestWorkout() {
        guard !isSeedingWorkout else { return }
        Task { @MainActor in
            isSeedingWorkout = true
            defer { isSeedingWorkout = false }
            do {
                // 권한 — 이전에 read 만 요청했더라도 write 까지 한 번 더 묻는다.
                try await HealthKitService.shared.requestAuthorization()

                let seeder = DebugWorkoutSeeder()
                let result = try await seeder.seedSingleMatch()

                // 새 워크아웃을 즉시 import → SwiftData 반영.
                await HealthKitService.shared.startObserver(modelContext: modelContext)

                let formatter = DateFormatter()
                formatter.locale = Locale(identifier: "ko_KR")
                formatter.dateFormat = "HH:mm"
                debugInfoMessage = """
                \(result.quarterCount)쿼터 시드 완료
                \(formatter.string(from: result.matchStart)) ~ \(formatter.string(from: result.matchEnd))
                매치 탭에서 확인하세요.
                """
            } catch {
                settingsErrorMessage = "시드 실패: \(error.localizedDescription)"
            }
        }
    }
    #endif

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
            _ = try await UserService.shared.fetchMe(into: modelContext)
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
