import SwiftUI

// JSX 의 KLPositionChips — GK/DF/MF/FW 포지션 선택 칩.
struct KLPositionChips: View {
    @Binding var selection: String  // "GK", "DF", "MF", "FW"
    private let positions = ["GK", "DF", "MF", "FW"]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(positions, id: \.self) { position in
                let isOn = position == selection
                Text(position)
                    .font(.system(size: 13, weight: .bold))
                    .tracking(0.3)
                    .foregroundStyle(isOn ? .white : KLTokens.text)
                    .frame(minWidth: 38)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        Capsule().fill(isOn ? KLTokens.pitch : KLTokens.chipBg)
                    )
                    .contentShape(Capsule())
                    .onTapGesture { selection = position }
            }
        }
    }
}

#Preview {
    @Previewable @State var pos = "MF"
    KLPositionChips(selection: $pos).padding()
}
