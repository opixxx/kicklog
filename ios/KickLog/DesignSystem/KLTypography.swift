import SwiftUI

// JSX 와이어프레임은 Pretendard + SF Pro Display 를 사용한다.
// iOS 시스템 폰트는 한글 자동으로 Apple SD Gothic Neo 로 매핑되므로 1차 포팅에서는 .system 으로 진행.
// 추후 Pretendard 를 번들에 추가하면 `.custom("Pretendard-...", size:)` 로 교체한다.
enum KLFont {

    // MARK: - Body (Pretendard / Apple SD Gothic Neo)

    static func body(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }

    static func largeTitle() -> Font {
        // KLNavBar 의 title: 34pt, weight 700, letterSpacing -0.8
        .system(size: 34, weight: .bold)
    }

    static func sectionTitle() -> Font {
        // KLSectionTitle: 20pt, weight 700, letterSpacing -0.5
        .system(size: 20, weight: .bold)
    }

    // MARK: - Numeric (SF Pro Display + tabular nums)

    // JSX 의 .kl-num 클래스 — tabular figures 적용.
    static func numeric(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight).monospacedDigit()
    }
}

// MARK: - LetterSpacing helpers (SwiftUI 의 .tracking)

extension View {
    func klTracking(_ value: CGFloat) -> some View {
        self.tracking(value)
    }
}
