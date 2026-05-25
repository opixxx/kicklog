import SwiftUI

// JSX 의 KLSettingsHeader / KLSettingsRow / KLSettingsGroup / KLToggle 를 한 파일에 통합.
// 모두 SettingsScreen 전용이라 별도 분리할 만큼 크지 않음.

// MARK: - 섹션 헤더

struct KLSettingsHeader: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 13))
            .tracking(-0.08)
            .foregroundStyle(KLTokens.textSec)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 36)
            .padding(.top, 20)
            .padding(.bottom, 6)
    }
}

// MARK: - 그룹 컨테이너

struct KLSettingsGroup<Content: View>: View {
    @ViewBuilder let content: () -> Content
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(spacing: 0) {
            content()
        }
        .background(KLTokens.bgElev)
        .clipShape(RoundedRectangle(cornerRadius: KLTokens.radiusCard))
        .padding(.horizontal, 16)
        .shadow(color: scheme == .dark ? .clear : .black.opacity(0.03), radius: 2, x: 0, y: 1)
    }
}

// MARK: - 설정 행

struct KLSettingsRow<Value: View>: View {
    let label: String
    var sub: String? = nil
    var icon: String? = nil
    var iconColor: Color = .white
    var iconBg: Color = .gray
    var badge: String? = nil
    var chevron: Bool = true
    var destructive: Bool = false
    var isLast: Bool = false
    @ViewBuilder let value: () -> Value

    var body: some View {
        HStack(spacing: 10) {
            if let icon {
                ZStack {
                    RoundedRectangle(cornerRadius: 7).fill(iconBg)
                        .frame(width: 28, height: 28)
                    KLIcon(name: icon, size: 16, color: iconColor)
                }
            }
            VStack(alignment: .leading, spacing: sub == nil ? 0 : 2) {
                Text(label)
                    .font(.system(size: 16))
                    .tracking(-0.3)
                    .foregroundStyle(destructive ? Color(hex: 0xFF3B30) : KLTokens.text)
                if let sub {
                    Text(sub)
                        .font(.system(size: 12))
                        .lineSpacing(2)
                        .foregroundStyle(KLTokens.textSec)
                }
            }
            Spacer(minLength: 0)
            if let badge {
                Text(badge)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(KLTokens.amber, in: Capsule())
            }
            value()
            if chevron {
                KLIcon(name: "chevron.right", size: 13, color: KLTokens.textTer)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .frame(minHeight: 44)
        .overlay(alignment: .bottom) {
            if !isLast {
                Rectangle()
                    .fill(KLTokens.sep)
                    .frame(height: 0.5)
                    .padding(.leading, icon == nil ? 16 : 54)
            }
        }
    }
}

// 편의 init — 우측 값이 String 인 경우
extension KLSettingsRow where Value == Text {
    init(
        label: String,
        sub: String? = nil,
        icon: String? = nil,
        iconColor: Color = .white,
        iconBg: Color = .gray,
        badge: String? = nil,
        chevron: Bool = true,
        destructive: Bool = false,
        isLast: Bool = false,
        value: String? = nil
    ) {
        self.label = label
        self.sub = sub
        self.icon = icon
        self.iconColor = iconColor
        self.iconBg = iconBg
        self.badge = badge
        self.chevron = chevron
        self.destructive = destructive
        self.isLast = isLast
        self.value = {
            Text(value ?? "")
                .font(.system(size: 15))
                .tracking(-0.2)
                .foregroundStyle(KLTokens.textSec)
        }
    }
}

// 편의 init — value 없음
extension KLSettingsRow where Value == EmptyView {
    init(
        labelOnly label: String,
        sub: String? = nil,
        icon: String? = nil,
        iconColor: Color = .white,
        iconBg: Color = .gray,
        badge: String? = nil,
        chevron: Bool = true,
        destructive: Bool = false,
        isLast: Bool = false
    ) {
        self.label = label
        self.sub = sub
        self.icon = icon
        self.iconColor = iconColor
        self.iconBg = iconBg
        self.badge = badge
        self.chevron = chevron
        self.destructive = destructive
        self.isLast = isLast
        self.value = { EmptyView() }
    }
}
