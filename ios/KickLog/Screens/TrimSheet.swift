import SwiftUI

// JSX 의 KLTrimSheetScreen — 쿼터 시간 조정.
// 감지된 워크아웃의 startedAt ~ endedAt 범위 안에서 사용자가 실제 출전 구간을 잘라낸다.
struct TrimSheet: View {
    let label: String                    // "Q2" 같은 표시 라벨
    let detectedStart: Date              // 감지된 워크아웃 전체 시작
    let detectedEnd: Date                // 감지된 워크아웃 전체 종료
    var onApply: (Date, Date) -> Void
    @Environment(\.dismiss) private var dismiss

    // slider 값 — 초 단위 offset from detectedStart
    @State private var startOffset: Double = 0
    @State private var endOffset: Double = 0
    private var totalDuration: Double {
        detectedEnd.timeIntervalSince(detectedStart)
    }

    var body: some View {
        VStack(spacing: 0) {
            grabber
            VStack(alignment: .leading, spacing: 0) {
                Text("\(label) 시간 조정")
                    .font(.system(size: 20, weight: .bold))
                    .tracking(-0.5)
                    .foregroundStyle(KLTokens.text)
                Text("실제 출전한 시간으로 맞춰주세요")
                    .font(.system(size: 13))
                    .foregroundStyle(KLTokens.textSec)
                    .padding(.top, 4)

                timeCard
                    .padding(.top, 22)

                sliderArea
                    .padding(.top, 24)

                buttonRow
                    .padding(.top, 28)
                    .padding(.bottom, 16)
            }
            .padding(.horizontal, 20)
        }
        .background(KLTokens.bgElev)
        .presentationDetents([.height(400)])
        .presentationDragIndicator(.hidden)
        .onAppear { initializeOffsets() }
    }

    private func initializeOffsets() {
        startOffset = 0
        endOffset = totalDuration
    }

    // MARK: - 시간 카드 (시작 · 조정 후 · 종료)

    private var timeCard: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text("시작")
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.4)
                    .foregroundStyle(KLTokens.textSec)
                    .textCase(.uppercase)
                Text(Self.timeFormatter.string(from: trimmedStart))
                    .font(KLFont.numeric(22, weight: .bold))
                    .tracking(-0.6)
                    .foregroundStyle(KLTokens.text)
                    .padding(.top, 2)
            }
            Spacer(minLength: 0)
            VStack(spacing: 1) {
                Text(adjustedDurationLabel)
                    .font(KLFont.numeric(14, weight: .bold))
                    .tracking(-0.2)
                    .foregroundStyle(KLTokens.pitch)
                Text("조정 후")
                    .font(.system(size: 11))
                    .foregroundStyle(KLTokens.textSec)
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 2) {
                Text("종료")
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.4)
                    .foregroundStyle(KLTokens.textSec)
                    .textCase(.uppercase)
                Text(Self.timeFormatter.string(from: trimmedEnd))
                    .font(KLFont.numeric(22, weight: .bold))
                    .tracking(-0.6)
                    .foregroundStyle(KLTokens.text)
                    .padding(.top, 2)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity)
        .background(KLTokens.bg, in: RoundedRectangle(cornerRadius: KLTokens.radiusCard))
    }

    private var trimmedStart: Date {
        detectedStart.addingTimeInterval(startOffset)
    }
    private var trimmedEnd: Date {
        detectedStart.addingTimeInterval(endOffset)
    }
    private var adjustedDurationLabel: String {
        let minutes = Int((endOffset - startOffset) / 60)
        return "\(minutes)분"
    }

    // MARK: - 슬라이더 영역 (tick + dual-thumb)

    private var sliderArea: some View {
        VStack(spacing: 6) {
            // tick marks (5분 단위)
            HStack {
                ForEach(tickMarks, id: \.self) { m in
                    Text("\(m)m").monospacedDigit()
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(KLTokens.textTer)
                    if m != tickMarks.last { Spacer(minLength: 0) }
                }
            }
            .padding(.horizontal, 4)

            KLDualThumbSlider(
                lower: $startOffset,
                upper: $endOffset,
                range: 0...totalDuration
            )
        }
    }

    // 5분 단위 tick (감지 총 시간 기반)
    private var tickMarks: [Int] {
        let totalMinutes = Int(totalDuration / 60)
        let step = max(5, ((totalMinutes / 6) / 5) * 5)
        var result = stride(from: 0, through: totalMinutes, by: step).map { $0 }
        // 마지막이 totalMinutes 보다 크면 truncate
        if let last = result.last, last > totalMinutes {
            result[result.count - 1] = totalMinutes
        }
        // 마지막 값 강제 추가
        if result.last != totalMinutes {
            result.append(totalMinutes)
        }
        return result
    }

    // MARK: - 버튼

    private var buttonRow: some View {
        GeometryReader { proxy in
            let totalWidth = proxy.size.width
            let spacing: CGFloat = 10
            HStack(spacing: spacing) {
                Button {
                    dismiss()
                } label: {
                    Text("취소")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(KLTokens.text)
                        .frame(width: (totalWidth - spacing) * 0.42, height: 50)
                        .background(KLTokens.chipBg, in: RoundedRectangle(cornerRadius: KLTokens.radiusBtn))
                }
                .buttonStyle(.plain)

                Button {
                    onApply(trimmedStart, trimmedEnd)
                    dismiss()
                } label: {
                    Text("적용하기")
                        .font(.system(size: 16, weight: .bold))
                        .tracking(-0.2)
                        .foregroundStyle(.white)
                        .frame(width: (totalWidth - spacing) * 0.58, height: 50)
                        .background(KLTokens.pitch, in: RoundedRectangle(cornerRadius: KLTokens.radiusBtn))
                }
                .buttonStyle(.plain)
            }
        }
        .frame(height: 50)
    }

    // MARK: - Grabber

    private var grabber: some View {
        Capsule()
            .fill(KLTokens.textTer)
            .frame(width: 36, height: 5)
            .padding(.top, 8)
            .padding(.bottom, 14)
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()
}
