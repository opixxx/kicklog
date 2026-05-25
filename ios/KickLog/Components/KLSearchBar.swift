import SwiftUI

// JSX 의 KLSearchBar — chip 형태의 검색 입력 + trailing 액션 버튼.
// 1차는 placeholder 만 표시 (실제 입력은 추후 단계).
struct KLSearchBar<Trailing: View>: View {
    let placeholder: String
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                KLIcon(name: "magnifyingglass", size: 16, color: KLTokens.textSec)
                Text(placeholder)
                    .font(.system(size: 15))
                    .foregroundStyle(KLTokens.textTer)
                    .frame(maxWidth: .infinity, alignment: .leading)
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
