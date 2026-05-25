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
                KLSettingsRow(label: "이름", value: me?.displayName ?? "—")
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
                    Toggle("", isOn: $hideHeartRate)
                        .labelsHidden()
                        .tint(KLTokens.pitch)
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
                KLSettingsRow(labelOnly: "계정 삭제",
                              sub: "30일 안에 다시 로그인하면 복구됩니다",
                              chevron: false, destructive: true, isLast: true)
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
