import SwiftUI

// JSX 의 KLQueueCard — Apple Watch 자동 감지된 라벨링 대기 경기 카드.
// pitch 그라디언트 + 우측 상단 축구장 라인 데코 + Q1·Q2·Q3·Q4 칩 + 라벨링 CTA.
struct KLQueueCard: View {
    let item: LabelingQueueItem
    var onTap: () -> Void = {}

    var body: some View {
        Button(action: onTap) {
            ZStack(alignment: .topTrailing) {
                // 우측 상단 축구장 라인 데코 (JSX 의 inline svg 와 동일 좌표)
                PitchLinesDecoration()
                    .stroke(Color.white.opacity(0.12), lineWidth: 1.5)
                    .frame(width: 120, height: 120)
                    .offset(x: 20, y: -10)

                VStack(alignment: .leading, spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.date)
                            .font(.system(size: 13, weight: .medium))
                            .tracking(-0.2)
                            .foregroundStyle(.white.opacity(0.85))
                        Text(item.time)
                            .font(KLFont.numeric(22, weight: .bold))
                            .tracking(-0.5)
                            .foregroundStyle(.white)
                    }

                    HStack(spacing: 5) {
                        Text(quartersLabel(item.detectedQuarters))
                            .monospacedDigit()
                        Text("감지됨")
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(.white.opacity(0.18), in: Capsule())

                    Spacer(minLength: 0)

                    HStack(spacing: 4) {
                        Spacer()
                        Text("라벨링")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                        KLIcon(name: "chevron.right", size: 14, color: .white)
                    }
                }
                .padding(16)
            }
            .frame(width: 280, height: 140)
            .background(
                LinearGradient(
                    colors: [KLTokens.pitch, KLTokens.pitchDeep],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: KLTokens.radiusCard, style: .continuous))
            .shadow(color: KLTokens.pitch.opacity(0.3), radius: 8, x: 0, y: 2)
        }
        .buttonStyle(.plain)
    }

    // "Q1·Q2·Q3·Q4" — 감지된 쿼터 수에 따라 동적으로 생성
    private func quartersLabel(_ count: Int) -> String {
        (1...max(count, 1)).map { "Q\($0)" }.joined(separator: "·")
    }
}

// MARK: - 축구장 라인 데코 Shape

private struct PitchLinesDecoration: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        // JSX viewBox 120x120 좌표를 rect 비율로 변환
        let scaleX = rect.width / 120
        let scaleY = rect.height / 120
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * scaleX, y: rect.minY + y * scaleY)
        }

        // 외곽 사각형 (10,10) → (110,110), corner radius 3
        path.addRoundedRect(
            in: CGRect(
                x: rect.minX + 10 * scaleX,
                y: rect.minY + 10 * scaleY,
                width: 100 * scaleX,
                height: 100 * scaleY
            ),
            cornerSize: CGSize(width: 3 * scaleX, height: 3 * scaleY)
        )
        // 중앙 가로선
        path.move(to: p(10, 60))
        path.addLine(to: p(110, 60))
        // 중앙 원 r=14
        path.addEllipse(in: CGRect(
            x: rect.minX + (60 - 14) * scaleX,
            y: rect.minY + (60 - 14) * scaleY,
            width: 28 * scaleX,
            height: 28 * scaleY
        ))
        return path
    }
}

#Preview {
    ScrollView(.horizontal) {
        HStack(spacing: 12) {
            ForEach(LabelingQueueItem.samples) { item in
                KLQueueCard(item: item)
            }
        }
        .padding(.horizontal, 20)
    }
    .background(KLTokens.bg)
}
