import SwiftUI

// JSX 의 KLStepper — capsule 형태의 −/+ 스텝퍼.
struct KLStepper: View {
    @Binding var value: Int
    var range: ClosedRange<Int> = 0...99

    var body: some View {
        HStack(spacing: 0) {
            Button(action: decrement) {
                Text("−")
                    .font(.system(size: 18))
                    .foregroundStyle(KLTokens.text)
                    .frame(width: 32, height: 30)
            }
            .buttonStyle(.plain)
            .disabled(value <= range.lowerBound)

            Text("\(value)")
                .font(KLFont.numeric(16, weight: .bold))
                .foregroundStyle(KLTokens.text)
                .frame(width: 36)

            Button(action: increment) {
                Text("+")
                    .font(.system(size: 18))
                    .foregroundStyle(KLTokens.text)
                    .frame(width: 32, height: 30)
            }
            .buttonStyle(.plain)
            .disabled(value >= range.upperBound)
        }
        .padding(2)
        .background(KLTokens.chipBg, in: Capsule())
    }

    private func decrement() {
        guard value > range.lowerBound else { return }
        value -= 1
    }

    private func increment() {
        guard value < range.upperBound else { return }
        value += 1
    }
}

#Preview {
    @Previewable @State var goals = 2
    KLStepper(value: $goals)
        .padding()
}
