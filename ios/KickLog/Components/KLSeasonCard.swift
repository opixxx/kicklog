import SwiftUI

// JSX 의 KLSeasonCard — 시즌 그리드의 통계 카드 컨테이너.
// 상단에 아이콘 + 라벨, 하단에 자유 콘텐츠.
struct KLSeasonCard<Content: View>: View {
    let icon: String
    var iconColor: Color? = nil
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                KLIcon(name: icon, size: 18, color: iconColor ?? KLTokens.pitch)
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .tracking(-0.2)
                    .foregroundStyle(KLTokens.textSec)
            }
            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .klCard()
    }
}
