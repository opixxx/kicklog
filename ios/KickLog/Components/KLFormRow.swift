import SwiftUI

// JSX 의 KLFormRow — 라벨링 폼의 키-값 행.
// 좌측 라벨(primary text), 우측 콘텐츠 (Segmented/Stepper/Chips 등).
struct KLFormRow<Content: View>: View {
    let label: String
    var isLast: Bool = false
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack(spacing: 12) {
            Text(label)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(KLTokens.text)
            Spacer(minLength: 0)
            content()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(minHeight: 50)
        .overlay(alignment: .bottom) {
            if !isLast {
                Rectangle()
                    .fill(KLTokens.sep)
                    .frame(height: 0.5)
                    .padding(.leading, 16)
            }
        }
    }
}
