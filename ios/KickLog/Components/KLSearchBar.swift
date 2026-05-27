import SwiftUI

// chip 형태의 검색 입력 + trailing 액션 버튼. text 바인딩이 비어있으면 placeholder, 비어있지 않으면 X 버튼.
struct KLSearchBar<Trailing: View>: View {
    let placeholder: String
    @Binding var text: String
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                KLIcon(name: "magnifyingglass", size: 16, color: KLTokens.textSec)
                TextField(placeholder, text: $text)
                    .font(.system(size: 15))
                    .foregroundStyle(KLTokens.text)
                    .submitLabel(.search)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                if !text.isEmpty {
                    Button(action: { text = "" }) {
                        KLIcon(name: "xmark.circle.fill", size: 16, color: KLTokens.textTer)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("검색어 지우기")
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(KLTokens.chipBg, in: RoundedRectangle(cornerRadius: 12))

            trailing()
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 14)
    }
}
