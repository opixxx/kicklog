import SwiftUI

// JSX 의 KLStatCardMini — 매치 상세 헤더 아래 2×2 그리드의 통계 카드.
// 아이콘 + 대형 숫자(30pt monospaced) + 단위 + 라벨.
struct KLStatCardMini: View {
    let icon: String
    var iconColor: Color? = nil
    let label: String
    let value: String
    var unit: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            KLIcon(name: icon, size: 22, color: iconColor ?? KLTokens.pitch)
            Spacer(minLength: 0)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(KLFont.numeric(30, weight: .bold))
                    .tracking(-1)
                    .foregroundStyle(KLTokens.text)
                if let unit {
                    Text(unit)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(KLTokens.textSec)
                }
            }
            Text(label)
                .font(.system(size: 13, weight: .medium))
                .tracking(-0.2)
                .foregroundStyle(KLTokens.textSec)
        }
        .frame(maxWidth: .infinity, minHeight: 116, alignment: .leading)
        .klCard()
    }
}

#Preview {
    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
        KLStatCardMini(icon: "figure.run", label: "이동거리", value: "3.2", unit: "km")
        KLStatCardMini(icon: "speedometer", label: "최고속도", value: "19.4", unit: "km/h")
        KLStatCardMini(icon: "bolt.fill", iconColor: KLTokens.amber, label: "스프린트", value: "14", unit: "회")
        KLStatCardMini(icon: "heart.fill", iconColor: KLTokens.red, label: "평균심박", value: "158", unit: "bpm")
    }
    .padding()
    .background(KLTokens.bg)
}
