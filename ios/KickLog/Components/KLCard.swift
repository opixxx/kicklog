import SwiftUI

// JSX 의 KLCard — 둥근 사각형 표면 + 그림자.
// SwiftUI 에서는 ViewModifier 로 제공해 어디든 `.klCard()` 한 줄로 적용 가능하게 한다.
struct KLCardStyle: ViewModifier {
    var padding: CGFloat
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: KLTokens.radiusCard, style: .continuous)
                    .fill(KLTokens.bgElev)
            )
            .klCardShadow(scheme)
    }
}

extension View {
    func klCard(padding: CGFloat = 16) -> some View {
        modifier(KLCardStyle(padding: padding))
    }
}

#Preview("Card") {
    VStack(alignment: .leading, spacing: 4) {
        Text("최근 경기")
            .font(.system(size: 17, weight: .semibold))
        Text("FC블루스 vs 우리 팀")
            .font(.system(size: 14))
            .foregroundStyle(KLTokens.textSec)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .klCard()
    .padding()
}
