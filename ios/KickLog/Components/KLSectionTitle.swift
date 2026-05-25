import SwiftUI

// JSX 의 KLSectionTitle — 섹션 헤더(좌측 정렬, 옵션 호박색 점).
// dot=true 일 때 amber + amberSoft 외광 효과를 ZStack 으로 구현.
struct KLSectionTitle: View {
    let text: String
    var hasDot: Bool = false

    var body: some View {
        HStack(spacing: 8) {
            Text(text)
                .font(KLFont.sectionTitle())
                .tracking(-0.5)
                .foregroundStyle(KLTokens.text)
            if hasDot {
                ZStack {
                    Circle()
                        .fill(KLTokens.amberSoft)
                        .frame(width: 16, height: 16)
                    Circle()
                        .fill(KLTokens.amber)
                        .frame(width: 8, height: 8)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 10)
    }
}

#Preview("Section Title") {
    VStack(alignment: .leading, spacing: 0) {
        KLSectionTitle(text: "라벨링 필요한 경기", hasDot: true)
        KLSectionTitle(text: "최근 경기")
    }
}
