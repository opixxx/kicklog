import SwiftUI

// JSX 의 KLMetaRow — 매치 상세 하단 키-값 리스트.
// 좌측 secondary 라벨, 우측 primary 값. 마지막 행은 separator 없음.
struct KLMetaRow<Value: View>: View {
    let key: String
    @ViewBuilder let value: () -> Value
    var isLast: Bool = false

    var body: some View {
        HStack {
            Text(key)
                .font(.system(size: 15))
                .foregroundStyle(KLTokens.textSec)
            Spacer()
            value()
                .font(.system(size: 15, weight: .semibold))
                .tracking(-0.2)
                .foregroundStyle(KLTokens.text)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .frame(minHeight: 44)
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

// 편의 init — 문자열 값
extension KLMetaRow where Value == Text {
    init(key: String, value: String, isLast: Bool = false) {
        self.init(key: key, value: { Text(value) }, isLast: isLast)
    }
}

#Preview {
    VStack(spacing: 0) {
        KLMetaRow(key: "상대팀", value: "FC블루스")
        KLMetaRow(key: "결과") {
            HStack(spacing: 2) {
                Text("4-2").monospacedDigit()
                Text("승")
            }
        }
        KLMetaRow(key: "포지션", value: "미드필더 (MF)")
        KLMetaRow(key: "골") { Text("2").monospacedDigit() }
        KLMetaRow(key: "어시스트") { Text("1").monospacedDigit() }
        KLMetaRow(key: "운동장", value: "마포 풋살장", isLast: true)
    }
    .background(KLTokens.bgElev)
    .clipShape(RoundedRectangle(cornerRadius: KLTokens.radiusCard))
    .padding()
    .background(KLTokens.bg)
}
