import SwiftUI

// JSX 의 KLQuarterChip — 라벨링 화면의 Q1~Q4 쿼터 선택 칩.
// 3가지 상태: on(pitch 배경 + 체크), off(점선 테두리), warn(amber 외곽 + 경고 뱃지).
struct KLQuarterChip: View {
    enum State {
        case on, off, warn
    }

    let quarter: String   // "Q1"
    let minutes: Int
    let state: State
    var onTap: () -> Void = {}

    var body: some View {
        Button(action: onTap) {
            content
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .on:
            base(fill: KLTokens.pitch, textColor: .white)
                .overlay(alignment: .topTrailing) {
                    KLIcon(name: "checkmark", size: 14, color: .white)
                        .padding(8)
                }
                .shadow(color: KLTokens.pitch.opacity(0.3), radius: 8, x: 0, y: 2)

        case .warn:
            base(fill: KLTokens.pitch, textColor: .white, minutesColor: KLTokens.amber, minutesSuffix: " ⚠")
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(KLTokens.amber, lineWidth: 2)
                )
                .overlay(alignment: .topTrailing) {
                    ZStack {
                        Circle()
                            .fill(KLTokens.amber)
                            .frame(width: 22, height: 22)
                        KLIcon(name: "exclamationmark.triangle.fill", size: 14, color: .white)
                    }
                    .offset(x: 8, y: -8)
                }
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(KLTokens.amberSoft, lineWidth: 4)
                )
                .shadow(color: KLTokens.pitch.opacity(0.3), radius: 8, x: 0, y: 2)

        case .off:
            base(fill: KLTokens.chipBg, textColor: KLTokens.textSec, minutesColor: KLTokens.textSec)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(KLTokens.textTer, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                )
        }
    }

    private func base(
        fill: Color,
        textColor: Color,
        minutesColor: Color? = nil,
        minutesSuffix: String = ""
    ) -> some View {
        VStack(spacing: 4) {
            Text(quarter)
                .font(KLFont.numeric(22, weight: .bold))
                .tracking(-0.4)
                .foregroundStyle(textColor)
            Text("\(minutes)분\(minutesSuffix)")
                .font(KLFont.numeric(12, weight: .semibold))
                .foregroundStyle(minutesColor ?? textColor.opacity(0.85))
        }
        .frame(maxWidth: .infinity)
        .frame(height: 78)
        .background(fill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

#Preview {
    HStack(spacing: 8) {
        KLQuarterChip(quarter: "Q1", minutes: 25, state: .on)
        KLQuarterChip(quarter: "Q2", minutes: 32, state: .warn)
        KLQuarterChip(quarter: "Q3", minutes: 25, state: .off)
        KLQuarterChip(quarter: "Q4", minutes: 24, state: .on)
    }
    .padding()
    .background(KLTokens.bg)
}
