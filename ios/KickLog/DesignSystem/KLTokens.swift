import SwiftUI

// JSX 와이어프레임의 `klTokens(dark)` 함수와 1:1 매핑되는 디자인 토큰.
// SwiftUI 의 자동 다크모드 전환을 활용하기 위해 light/dark 컬러를 한번에 정의한다.
enum KLTokens {

    // MARK: - Brand

    static let pitch = Color(hex: 0x1B5E20)
    static let pitchDeep = Color(hex: 0x103D14)
    static let pitchSoft = Color(
        light: Color(hex: 0x1B5E20, opacity: 0.10),
        dark: Color(hex: 0x2E7D32, opacity: 0.22)
    )
    static let amber = Color(hex: 0xFFB300)
    static let amberSoft = Color(
        light: Color(hex: 0xFFB300, opacity: 0.16),
        dark: Color(hex: 0xFFB300, opacity: 0.20)
    )
    static let red = Color(
        light: Color(hex: 0xE53935),
        dark: Color(hex: 0xFF6B6B)
    )
    static let gray = Color(hex: 0x8E8E93)

    // MARK: - Surfaces

    static let bg = Color(
        light: Color(hex: 0xF2F2F7),
        dark: Color(hex: 0x000000)
    )
    static let bgElev = Color(
        light: Color(hex: 0xFFFFFF),
        dark: Color(hex: 0x1C1C1E)
    )
    static let bgElev2 = Color(
        light: Color(hex: 0xFFFFFF),
        dark: Color(hex: 0x2C2C2E)
    )
    static let chipBg = Color(
        light: Color(hex: 0xEEF0F3),
        dark: Color(hex: 0x2C2C2E)
    )

    // MARK: - Text

    static let text = Color(
        light: Color(hex: 0x000000),
        dark: Color(hex: 0xFFFFFF)
    )
    static let textSec = Color(
        light: Color(hex: 0x3C3C43, opacity: 0.60),
        dark: Color(hex: 0xEBEBF5, opacity: 0.60)
    )
    static let textTer = Color(
        light: Color(hex: 0x3C3C43, opacity: 0.30),
        dark: Color(hex: 0xEBEBF5, opacity: 0.30)
    )
    static let textQuat = Color(
        light: Color(hex: 0x3C3C43, opacity: 0.18),
        dark: Color(hex: 0xEBEBF5, opacity: 0.18)
    )

    // MARK: - Strokes

    static let sep = Color(
        light: Color(hex: 0x3C3C43, opacity: 0.18),
        dark: Color(hex: 0x545458, opacity: 0.55)
    )
    static let hair = Color(
        light: Color(hex: 0x000000, opacity: 0.06),
        dark: Color(hex: 0xFFFFFF, opacity: 0.08)
    )

    // MARK: - Result chips (승/무/패)

    static let winBg = Color(
        light: Color(hex: 0x1B5E20, opacity: 0.12),
        dark: Color(hex: 0x2E7D32, opacity: 0.30)
    )
    static let winFg = Color(
        light: Color(hex: 0x1B5E20),
        dark: Color(hex: 0x9BE39E)
    )
    static let drawBg = Color(
        light: Color(hex: 0x3C3C43, opacity: 0.10),
        dark: Color(hex: 0xFFFFFF, opacity: 0.12)
    )
    static let drawFg = Color(
        light: Color(hex: 0x3C3C43, opacity: 0.80),
        dark: Color(hex: 0xEBEBF5, opacity: 0.85)
    )
    static let loseBg = Color(
        light: Color(hex: 0xE53935, opacity: 0.10),
        dark: Color(hex: 0xE53935, opacity: 0.20)
    )
    static let loseFg = Color(
        light: Color(hex: 0xC62828),
        dark: Color(hex: 0xFF6B6B)
    )

    // MARK: - Geometry

    static let radiusCard: CGFloat = 14
    static let radiusBtn: CGFloat = 12

    // MARK: - Shadows

    static func cardShadow(_ scheme: ColorScheme) -> ShadowSpec {
        scheme == .dark
            ? ShadowSpec(color: .black.opacity(0.4), radius: 2, x: 0, y: 1)
            : ShadowSpec(color: .black.opacity(0.04), radius: 3, x: 0, y: 1)
    }
}

// MARK: - Shadow Spec

struct ShadowSpec {
    let color: Color
    let radius: CGFloat
    let x: CGFloat
    let y: CGFloat
}

extension View {
    func klCardShadow(_ scheme: ColorScheme) -> some View {
        let s = KLTokens.cardShadow(scheme)
        return self.shadow(color: s.color, radius: s.radius, x: s.x, y: s.y)
    }
}

// MARK: - Color helpers

extension Color {
    // 16진수 정수 리터럴(0xRRGGBB) → Color. JSX 의 '#RRGGBB' 표기를 그대로 옮기기 위해 사용.
    init(hex: UInt32, opacity: Double = 1.0) {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >> 8) & 0xFF) / 255.0
        let b = Double(hex & 0xFF) / 255.0
        self.init(.sRGB, red: r, green: g, blue: b, opacity: opacity)
    }

    // 라이트/다크 모드별 색을 한번에 선언. UITraitCollection 기반으로 시스템이 자동 전환한다.
    init(light: Color, dark: Color) {
        #if canImport(UIKit)
        self.init(uiColor: UIColor { trait in
            trait.userInterfaceStyle == .dark
                ? UIColor(dark)
                : UIColor(light)
        })
        #else
        self = light
        #endif
    }
}
