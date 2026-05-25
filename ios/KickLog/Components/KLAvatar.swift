import SwiftUI

// JSX 의 KLAvatar — 이름 첫 글자 + 컬러 팔레트 기반 원형 아바타.
// 다크 모드에서는 단일 흰색 톤으로 통일.
struct KLAvatar: View {
    let name: String
    var size: CGFloat = 44
    @Environment(\.colorScheme) private var scheme

    struct PaletteColor { let bg: Color; let fg: Color }

    private static let palette: [PaletteColor] = {
        var p: [PaletteColor] = []
        p.append(PaletteColor(bg: Color(hex: 0xE8F0FE), fg: Color(hex: 0x1A56DB)))
        p.append(PaletteColor(bg: Color(hex: 0xFFF4E5), fg: Color(hex: 0xB45309)))
        p.append(PaletteColor(bg: Color(hex: 0xEAF7EC), fg: Color(hex: 0x1B5E20)))
        p.append(PaletteColor(bg: Color(hex: 0xFCE7E7), fg: Color(hex: 0xB91C1C)))
        p.append(PaletteColor(bg: Color(hex: 0xF0E8FE), fg: Color(hex: 0x6D28D9)))
        p.append(PaletteColor(bg: Color(hex: 0xE0F7FA), fg: Color(hex: 0x00838F)))
        return p
    }()

    private var paletteColor: PaletteColor {
        let key = (Int(name.first?.unicodeScalars.first?.value ?? 0) + name.count) % Self.palette.count
        return Self.palette[key]
    }

    private var initial: String {
        String(name.prefix(1))
    }

    var body: some View {
        Text(initial)
            .font(.system(size: size * 0.4, weight: .bold))
            .tracking(-0.4)
            .foregroundStyle(scheme == .dark ? .white : paletteColor.fg)
            .frame(width: size, height: size)
            .background(
                Circle().fill(scheme == .dark ? Color.white.opacity(0.08) : paletteColor.bg)
            )
    }
}

#Preview {
    HStack {
        ForEach(["김", "이", "박", "최", "정", "박"], id: \.self) { c in
            KLAvatar(name: c)
        }
    }
    .padding()
}
