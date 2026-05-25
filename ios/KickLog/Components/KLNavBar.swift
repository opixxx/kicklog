import SwiftUI

// JSX 의 KLNavBar — iOS large title 스타일.
// trailing/leading 액션이 타이틀 위에 줄로 분리되어 표시되는 형태(시스템 nav bar 와는 다른 커스텀 레이아웃).
struct KLNavBar<Leading: View, Trailing: View>: View {
    let title: String
    var subtitle: String? = nil
    var paddingTop: CGFloat = 8
    @ViewBuilder let leading: () -> Leading
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if Leading.self != EmptyView.self || Trailing.self != EmptyView.self {
                HStack {
                    leading()
                    Spacer(minLength: 0)
                    HStack(spacing: 14) {
                        trailing()
                    }
                }
                .frame(minHeight: 32)
                .padding(.bottom, 6)
            }

            Text(title)
                .font(KLFont.largeTitle())
                .tracking(-0.8)
                .foregroundStyle(KLTokens.text)
                .lineSpacing(2)

            if let subtitle {
                Text(subtitle)
                    .font(KLFont.body(15))
                    .tracking(-0.2)
                    .foregroundStyle(KLTokens.textSec)
                    .padding(.top, 4)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, paddingTop)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - 편의 생성자 (leading 또는 trailing 없는 경우)

extension KLNavBar where Leading == EmptyView, Trailing == EmptyView {
    init(title: String, subtitle: String? = nil, paddingTop: CGFloat = 8) {
        self.init(
            title: title,
            subtitle: subtitle,
            paddingTop: paddingTop,
            leading: { EmptyView() },
            trailing: { EmptyView() }
        )
    }
}

extension KLNavBar where Leading == EmptyView {
    init(
        title: String,
        subtitle: String? = nil,
        paddingTop: CGFloat = 8,
        @ViewBuilder trailing: @escaping () -> Trailing
    ) {
        self.init(
            title: title,
            subtitle: subtitle,
            paddingTop: paddingTop,
            leading: { EmptyView() },
            trailing: trailing
        )
    }
}

#Preview("NavBar") {
    VStack(spacing: 0) {
        KLNavBar(title: "경기", subtitle: "2026 시즌 · 14경기") {
            HStack(spacing: 12) {
                KLIcon(name: "magnifyingglass", size: 22, color: KLTokens.pitch)
                KLIcon(name: "plus.circle.fill", size: 26, color: KLTokens.pitch)
            }
        }
        Divider()
        KLNavBar(title: "친구")
    }
}
