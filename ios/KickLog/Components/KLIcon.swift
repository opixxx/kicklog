import SwiftUI

// JSX 의 인라인 SVG 아이콘은 대부분 SF Symbols 와 1:1 대응되므로 매핑 테이블로 처리한다.
// 일부(tab.matches, watch, kakao.bubble 등)는 가장 유사한 SF Symbol 로 치환했다.
struct KLIcon: View {
    let name: String
    var size: CGFloat = 22
    var weight: Font.Weight = .medium
    var color: Color? = nil

    var body: some View {
        Image(systemName: Self.resolve(name))
            .font(.system(size: size, weight: weight))
            .foregroundStyle(color ?? .primary)
            .accessibilityHidden(true)
    }

    // MARK: - JSX 이름 → SF Symbol 매핑

    static func resolve(_ name: String) -> String {
        switch name {
        // Tab bar — JSX 의 커스텀 드로잉을 가장 유사한 SF Symbol 로 치환
        case "tab.matches": return "sportscourt"
        case "tab.season": return "chart.line.uptrend.xyaxis"
        case "tab.friends": return "person.2.fill"
        case "tab.settings": return "gearshape.fill"

        // JSX 이름이 SF Symbol 명과 다른 경우
        case "chart.line.uptrend": return "chart.line.uptrend.xyaxis"
        case "watch": return "applewatch"
        case "kakao.bubble": return "bubble.left.fill"
        case "apple.logo": return "applelogo"
        case "heart.text.square": return "heart.text.square.fill"

        // 나머지는 JSX 이름이 SF Symbol 명과 동일 — 그대로 사용
        // figure.run, speedometer, bolt.fill, heart.fill, soccerball,
        // soccerball.inverse, trophy.fill, calendar, star.fill,
        // chevron.right, chevron.down, magnifyingglass, plus, plus.circle.fill,
        // checkmark, xmark, exclamationmark.triangle.fill,
        // person.crop.circle.fill, gearshape.fill, link, figure.soccer
        default: return name
        }
    }
}

private struct KLIconGalleryPreview: View {
    private let names = [
        "figure.run", "speedometer", "bolt.fill", "heart.fill",
        "soccerball", "trophy.fill", "calendar", "chart.line.uptrend",
        "star.fill", "chevron.right", "magnifyingglass", "plus.circle.fill",
        "checkmark", "xmark", "person.crop.circle.fill", "gearshape.fill",
        "tab.matches", "tab.season", "tab.friends", "tab.settings",
        "apple.logo", "kakao.bubble", "watch", "figure.soccer"
    ]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 80))], spacing: 16) {
                ForEach(names, id: \.self) { name in
                    VStack(spacing: 6) {
                        KLIcon(name: name, size: 28, color: KLTokens.pitch)
                        Text(name)
                            .font(.system(size: 10))
                            .foregroundStyle(KLTokens.textSec)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
            }
            .padding()
        }
    }
}

#Preview("아이콘 갤러리") {
    KLIconGalleryPreview()
}
