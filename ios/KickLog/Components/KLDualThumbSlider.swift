import SwiftUI

// JSX 의 dual-thumb slider — 시작/종료 두 핸들 + pitch 진행 막대.
// Trim sheet 에서 쿼터 시간 조정 (start ~ end) 에 사용.
struct KLDualThumbSlider: View {
    @Binding var lower: Double      // 현재 lower 값 (range.lowerBound ~ upper)
    @Binding var upper: Double      // 현재 upper 값 (lower ~ range.upperBound)
    let range: ClosedRange<Double>
    var minimumGap: Double = 60     // 최소 간격 (초 단위 — 1분)
    var thumbSize: CGFloat = 30
    var trackHeight: CGFloat = 4

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let span = range.upperBound - range.lowerBound
            let lowerX = max(0, min(width, CGFloat((lower - range.lowerBound) / span) * width))
            let upperX = max(0, min(width, CGFloat((upper - range.lowerBound) / span) * width))

            ZStack(alignment: .leading) {
                // 전체 track
                Capsule()
                    .fill(KLTokens.chipBg)
                    .frame(height: trackHeight)

                // 선택 구간 (pitch)
                Capsule()
                    .fill(KLTokens.pitch)
                    .frame(width: max(0, upperX - lowerX), height: trackHeight)
                    .offset(x: lowerX)

                // 시작 thumb
                thumb
                    .position(x: lowerX, y: thumbSize / 2)
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                let clampedX = max(0, min(value.location.x, upperX - thumbSize / 2))
                                let newValue = range.lowerBound + Double(clampedX / width) * span
                                let bounded = min(newValue, upper - minimumGap)
                                lower = max(range.lowerBound, bounded)
                            }
                    )

                // 종료 thumb
                thumb
                    .position(x: upperX, y: thumbSize / 2)
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                let clampedX = max(lowerX + thumbSize / 2, min(value.location.x, width))
                                let newValue = range.lowerBound + Double(clampedX / width) * span
                                let bounded = max(newValue, lower + minimumGap)
                                upper = min(range.upperBound, bounded)
                            }
                    )
            }
        }
        .frame(height: thumbSize)
    }

    private var thumb: some View {
        Circle()
            .fill(.white)
            .frame(width: thumbSize, height: thumbSize)
            .shadow(color: .black.opacity(0.18), radius: 6, x: 0, y: 2)
            .overlay(Circle().stroke(.black.opacity(0.05), lineWidth: 0.5))
    }
}

#Preview {
    @Previewable @State var lower: Double = 60
    @Previewable @State var upper: Double = 1500
    VStack(spacing: 24) {
        KLDualThumbSlider(lower: $lower, upper: $upper, range: 0...1800)
        HStack {
            Text("lower: \(Int(lower / 60))분 \(Int(lower) % 60)초")
            Spacer()
            Text("upper: \(Int(upper / 60))분 \(Int(upper) % 60)초")
        }
        .font(.system(size: 12).monospacedDigit())
    }
    .padding()
}
