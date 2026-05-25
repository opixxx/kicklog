import SwiftUI

// JSX 의 KLBarChart — Q1~Q4 쿼터별 막대 차트.
// Swift Charts 대신 SwiftUI 기본 도형으로 직접 그려 JSX 와 픽셀 단위로 일치시킨다.
// (값 라벨 위치, amber 최대값 강조 스트라이프, 점선 그리드까지 세밀 제어 필요)
struct KLBarChart: View {
    let title: String
    let unit: String
    let values: [Double]
    let labels: [String]
    var formatValue: (Double) -> String = { String(format: "%.1f", $0) }

    private let chartHeight: CGFloat = 130
    private let padTop: CGFloat = 26
    private let padBottom: CGFloat = 26
    private let barWidth: CGFloat = 36

    private var innerHeight: CGFloat { chartHeight - padTop - padBottom }
    private var scaleMax: Double { (values.max() ?? 1) * 1.18 }
    private var maxIndex: Int {
        values.enumerated().max(by: { $0.element < $1.element })?.offset ?? 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .tracking(-0.3)
                    .foregroundStyle(KLTokens.text)
                Spacer()
                Text("단위 · \(unit)")
                    .font(.system(size: 12).monospacedDigit())
                    .foregroundStyle(KLTokens.textSec)
            }

            ZStack(alignment: .bottom) {
                gridlines
                HStack(spacing: 0) {
                    ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                        column(index: index, value: value)
                    }
                }
            }
            .frame(height: chartHeight)
        }
    }

    // MARK: - 그리드선 (25/50/75 점선 + 100 실선)

    private var gridlines: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            ForEach([0.25, 0.5, 0.75, 1.0] as [CGFloat], id: \.self) { fraction in
                let y = padTop + innerHeight * (1 - fraction)
                Path { path in
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: w, y: y))
                }
                .stroke(
                    KLTokens.hair,
                    style: StrokeStyle(
                        lineWidth: 1,
                        dash: fraction >= 1.0 ? [] : [2, 3]
                    )
                )
            }
        }
    }

    // MARK: - 단일 막대 컬럼 (값 라벨 + 막대 + X축 라벨)

    private func column(index: Int, value: Double) -> some View {
        VStack(spacing: 0) {
            // 값 라벨
            Text(formatValue(value))
                .font(.system(size: 13, weight: .bold).monospacedDigit())
                .tracking(-0.2)
                .foregroundStyle(KLTokens.text)
                .frame(height: padTop, alignment: .center)

            // 막대 영역 — 하단 정렬, 빈 공간은 위쪽으로
            ZStack(alignment: .bottom) {
                Color.clear.frame(height: innerHeight)
                ZStack(alignment: .top) {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(KLTokens.pitch)
                        .frame(width: barWidth, height: barHeight(for: value))
                    if index == maxIndex {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(KLTokens.amber)
                            .frame(width: barWidth, height: 4)
                    }
                }
            }
            .frame(maxWidth: .infinity)

            // X축 라벨
            Text(labels[safe: index] ?? "")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(KLTokens.textSec)
                .frame(height: padBottom, alignment: .center)
        }
    }

    private func barHeight(for value: Double) -> CGFloat {
        guard scaleMax > 0 else { return 0 }
        return CGFloat(value / scaleMax) * innerHeight
    }
}

// MARK: - 안전 인덱스 접근

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

#Preview {
    VStack(spacing: 10) {
        KLBarChart(
            title: "평균 속도",
            unit: "km/h",
            values: [7.2, 6.8, 6.5, 6.1],
            labels: ["Q1", "Q2", "Q3", "Q4"]
        )
        .klCard()

        KLBarChart(
            title: "평균 심박",
            unit: "bpm",
            values: [152, 158, 162, 165],
            labels: ["Q1", "Q2", "Q3", "Q4"],
            formatValue: { String(Int($0)) }
        )
        .klCard()

        KLBarChart(
            title: "스프린트 횟수",
            unit: "회",
            values: [4, 5, 3, 2],
            labels: ["Q1", "Q2", "Q3", "Q4"],
            formatValue: { String(Int($0)) }
        )
        .klCard()
    }
    .padding()
    .background(KLTokens.bg)
}
