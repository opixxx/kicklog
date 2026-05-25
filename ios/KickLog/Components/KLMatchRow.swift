import SwiftUI

// JSX 의 KLMatchRow — 경기 리스트 한 행.
// 날짜 컬럼 + 상대팀/운동장 + 결과 칩 + chevron, 하단에 sub-stats 줄.
struct KLMatchRow: View {
    let match: Match
    var isLast: Bool = false
    var onTap: () -> Void = {}

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 14) {
                    // 날짜 컬럼
                    VStack(alignment: .leading, spacing: 3) {
                        Text(match.dateNum)
                            .font(KLFont.numeric(22, weight: .bold))
                            .tracking(-0.6)
                            .foregroundStyle(KLTokens.text)
                        Text(match.dow)
                            .font(.system(size: 12))
                            .foregroundStyle(KLTokens.textSec)
                    }
                    .frame(minWidth: 38, alignment: .leading)

                    // 상대팀 + 운동장
                    VStack(alignment: .leading, spacing: 2) {
                        Text(match.opponent)
                            .font(.system(size: 17, weight: .semibold))
                            .tracking(-0.4)
                            .foregroundStyle(KLTokens.text)
                        Text(match.venue)
                            .font(.system(size: 13))
                            .foregroundStyle(KLTokens.textSec)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    // 결과 칩
                    KLChip(bg: resultBg, fg: resultFg, size: .md) {
                        Text(match.score).monospacedDigit()
                        Text(match.result.rawValue)
                            .padding(.leading, 2)
                    }

                    KLIcon(name: "chevron.right", size: 14, color: KLTokens.textTer)
                }

                // sub-stats 줄
                HStack(spacing: 0) {
                    StatPiece(text: "\(formatted(match.distanceKm))km")
                    StatDot()
                    StatPiece(text: "\(formatted(match.avgSpeedKmh))km/h")
                    StatDot()
                    StatPiece(text: "\(match.sprintCount)회")
                    StatDot()
                    StatPiece(text: "\(match.avgHeartRateBpm)bpm")
                }
                .font(.system(size: 12).monospacedDigit())
                .foregroundStyle(KLTokens.textSec)
                .padding(.leading, 52)
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 16)
            .overlay(alignment: .bottom) {
                if !isLast {
                    Rectangle()
                        .fill(KLTokens.sep)
                        .frame(height: 0.5)
                        .padding(.leading, 20)
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - 결과별 색

    private var resultBg: Color {
        switch match.result {
        case .win: return KLTokens.winBg
        case .draw: return KLTokens.drawBg
        case .lose: return KLTokens.loseBg
        }
    }

    private var resultFg: Color {
        switch match.result {
        case .win: return KLTokens.winFg
        case .draw: return KLTokens.drawFg
        case .lose: return KLTokens.loseFg
        }
    }

    // 소수점 1자리 (JSX 표기 그대로)
    private func formatted(_ value: Double) -> String {
        String(format: "%.1f", value)
    }
}

// MARK: - sub-stats 보조 컴포넌트

private struct StatPiece: View {
    let text: String
    var body: some View {
        Text(text)
    }
}

private struct StatDot: View {
    var body: some View {
        Text("·")
            .foregroundStyle(KLTokens.textTer)
            .padding(.horizontal, 6)
    }
}

#Preview {
    VStack(spacing: 0) {
        ForEach(Array(Match.samples.enumerated()), id: \.element.id) { index, match in
            KLMatchRow(match: match, isLast: index == Match.samples.count - 1)
        }
    }
    .background(KLTokens.bgElev)
    .clipShape(RoundedRectangle(cornerRadius: KLTokens.radiusCard))
    .padding()
    .background(KLTokens.bg)
}
