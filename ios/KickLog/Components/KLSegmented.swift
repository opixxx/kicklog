import SwiftUI

// JSX 의 KLSegmented — iOS Picker 의 segmented 스타일과 유사한 커스텀 컴포넌트.
// 라벨링 화면의 승/무/패 토글에 사용.
struct KLSegmented<Option: Hashable & CustomStringConvertible>: View {
    let options: [Option]
    @Binding var selection: Option
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.self) { option in
                let isOn = option == selection
                Text(option.description)
                    .font(.system(size: 14, weight: isOn ? .semibold : .medium))
                    .foregroundStyle(KLTokens.text)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 7)
                            .fill(isOn ? selectedBackground : Color.clear)
                            .shadow(
                                color: isOn && scheme == .light ? .black.opacity(0.1) : .clear,
                                radius: 3, x: 0, y: 1
                            )
                    )
                    .contentShape(Rectangle())
                    .onTapGesture { selection = option }
            }
        }
        .padding(2)
        .background(KLTokens.chipBg, in: RoundedRectangle(cornerRadius: 9))
    }

    private var selectedBackground: Color {
        scheme == .dark ? Color(hex: 0x48484A) : .white
    }
}

// MatchResult 사용 시 편의
extension MatchResult: CustomStringConvertible {
    public var description: String { rawValue }
}
