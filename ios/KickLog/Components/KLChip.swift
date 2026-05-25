import SwiftUI

// JSX 의 KLChip — 라운드 캡슐 형태의 라벨/뱃지.
// 승/무/패 결과 칩, 시간 칩, 라벨 칩 등 전반에 사용된다.
struct KLChip<Content: View>: View {

    enum Size {
        case sm, md, lg

        var fontSize: CGFloat {
            switch self {
            case .sm: return 12
            case .md: return 13
            case .lg: return 15
            }
        }

        var fontWeight: Font.Weight {
            switch self {
            case .sm, .md: return .semibold
            case .lg: return .bold
            }
        }

        var paddingH: CGFloat {
            switch self {
            case .sm: return 8
            case .md: return 10
            case .lg: return 12
            }
        }

        var paddingV: CGFloat {
            switch self {
            case .sm: return 3
            case .md: return 4
            case .lg: return 6
            }
        }
    }

    let bg: Color
    let fg: Color
    var size: Size = .md
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack(spacing: 4) {
            content()
        }
        .font(.system(size: size.fontSize, weight: size.fontWeight))
        .tracking(-0.2)
        .foregroundStyle(fg)
        .padding(.horizontal, size.paddingH)
        .padding(.vertical, size.paddingV)
        .background(bg, in: Capsule())
    }
}

#Preview("Chip 변형") {
    VStack(spacing: 12) {
        KLChip(bg: KLTokens.winBg, fg: KLTokens.winFg, size: .md) {
            Text("4-2").monospacedDigit()
            Text("승")
        }
        KLChip(bg: KLTokens.drawBg, fg: KLTokens.drawFg, size: .md) {
            Text("2-2").monospacedDigit()
            Text("무")
        }
        KLChip(bg: KLTokens.loseBg, fg: KLTokens.loseFg, size: .md) {
            Text("1-3").monospacedDigit()
            Text("패")
        }
        KLChip(bg: KLTokens.amberSoft, fg: KLTokens.amber, size: .sm) {
            Text("라벨링 필요")
        }
    }
    .padding()
}
