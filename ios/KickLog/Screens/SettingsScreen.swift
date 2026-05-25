import SwiftUI

// 설정 탭 — Form 스타일 리스트.
// JSX settings.jsx 와 동일 구조 + iOS native Toggle 사용.
struct SettingsScreen: View {
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
            KLAvatar(name: "김조축", size: 56)
            VStack(alignment: .leading, spacing: 2) {
                Text("김조축")
                    .font(.system(size: 20, weight: .bold))
                    .tracking(-0.4)
                    .foregroundStyle(KLTokens.text)
                (Text("2026").monospacedDigit() + Text("년 ") + Text("1").monospacedDigit() + Text("월부터 함께"))
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

    // MARK: - 섹션들

    private var profileSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            KLSettingsHeader(text: "프로필")
            KLSettingsGroup {
                KLSettingsRow(label: "이름", value: "김조축")
                KLSettingsRow(label: "이메일", chevron: false,
                              value: "abc@privaterelay.appleid.com")
                KLSettingsRow(label: "가입일", chevron: false, isLast: true,
                              value: "2026년 1월 2일")
            }
        }
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
        VStack(alignment: .leading, spacing: 0) {
            KLSettingsHeader(text: "데이터")
            KLSettingsGroup {
                KLSettingsRow(labelOnly: "동기화 대기",
                              sub: "네트워크가 안정되면 자동으로 재시도합니다",
                              badge: "2건",
                              isLast: true)
            }
        }
    }

    private var accountSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            KLSettingsHeader(text: "계정")
            KLSettingsGroup {
                KLSettingsRow(labelOnly: "로그아웃", chevron: false)
                KLSettingsRow(labelOnly: "계정 삭제",
                              sub: "30일 안에 다시 로그인하면 복구됩니다",
                              chevron: false, destructive: true, isLast: true)
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
