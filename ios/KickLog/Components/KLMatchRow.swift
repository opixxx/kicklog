import SwiftUI

// 경기 리스트 행에 필요한 표시 데이터.
// SampleMatch / SwiftData Match 양쪽 다 `.rowData` 로 변환해 전달한다.
struct MatchRowData {
    let dateNum: String
    let dow: String
    let opponent: String
    let venue: String
    let result: MatchResult
    let score: String
    let distanceKm: Double
    let avgSpeedKmh: Double
    let sprintCount: Int
    let avgHeartRateBpm: Int
}

// MARK: - SampleMatch → MatchRowData

extension SampleMatch {
    var rowData: MatchRowData {
        MatchRowData(
            dateNum: dateNum, dow: dow,
            opponent: opponent, venue: venue,
            result: result, score: score,
            distanceKm: distanceKm, avgSpeedKmh: avgSpeedKmh,
            sprintCount: sprintCount, avgHeartRateBpm: avgHeartRateBpm
        )
    }
}

// MARK: - SwiftData Match → MatchRowData

extension Match {
    var rowData: MatchRowData {
        MatchRowData(
            dateNum: Self.dateNumFormatter.string(from: playedAt),
            dow: Self.dowFormatter.string(from: playedAt),
            opponent: opponentName ?? "—",
            venue: "—",                         // venueId → Venue.name 은 후속 (Service 필요)
            result: MatchResult.from(result),
            score: userGoals.map { "\($0)점" } ?? "—",
            distanceKm: Double(totalDistanceM) / 1000.0,
            avgSpeedKmh: maxSpeedKmh,           // 헤드라인은 max — 평균은 quarter 단위
            sprintCount: sprintCount,
            avgHeartRateBpm: avgHeartRate
        )
    }

    private static let dateNumFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "M/d"
        return f
    }()

    private static let dowFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ko_KR")
        f.dateFormat = "E"
        return f
    }()
}

// MARK: - String("W"/"D"/"L") → MatchResult

extension MatchResult {
    static func from(_ code: String?) -> MatchResult {
        switch code {
        case "W": return .win
        case "L": return .lose
        case "D": return .draw
        default: return .draw                   // 미라벨링 — 일단 draw 색으로 표시
        }
    }
}

// MARK: - 경기 행 View

struct KLMatchRow: View {
    let data: MatchRowData
    var isLast: Bool = false
    var onTap: () -> Void = {}

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(data.dateNum)
                            .font(KLFont.numeric(22, weight: .bold))
                            .tracking(-0.6)
                            .foregroundStyle(KLTokens.text)
                        Text(data.dow)
                            .font(.system(size: 12))
                            .foregroundStyle(KLTokens.textSec)
                    }
                    .frame(minWidth: 38, alignment: .leading)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(data.opponent)
                            .font(.system(size: 17, weight: .semibold))
                            .tracking(-0.4)
                            .foregroundStyle(KLTokens.text)
                        Text(data.venue)
                            .font(.system(size: 13))
                            .foregroundStyle(KLTokens.textSec)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    KLChip(bg: resultBg, fg: resultFg, size: .md) {
                        Text(data.score).monospacedDigit()
                        Text(data.result.rawValue).padding(.leading, 2)
                    }

                    KLIcon(name: "chevron.right", size: 14, color: KLTokens.textTer)
                }

                HStack(spacing: 0) {
                    StatPiece(text: "\(formatted(data.distanceKm))km")
                    StatDot()
                    StatPiece(text: "\(formatted(data.avgSpeedKmh))km/h")
                    StatDot()
                    StatPiece(text: "\(data.sprintCount)회")
                    StatDot()
                    StatPiece(text: "\(data.avgHeartRateBpm)bpm")
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

    private var resultBg: Color {
        switch data.result {
        case .win: return KLTokens.winBg
        case .draw: return KLTokens.drawBg
        case .lose: return KLTokens.loseBg
        }
    }

    private var resultFg: Color {
        switch data.result {
        case .win: return KLTokens.winFg
        case .draw: return KLTokens.drawFg
        case .lose: return KLTokens.loseFg
        }
    }

    private func formatted(_ value: Double) -> String {
        String(format: "%.1f", value)
    }
}

private struct StatPiece: View {
    let text: String
    var body: some View { Text(text) }
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
        ForEach(Array(SampleMatch.samples.enumerated()), id: \.element.id) { index, match in
            KLMatchRow(data: match.rowData, isLast: index == SampleMatch.samples.count - 1)
        }
    }
    .background(KLTokens.bgElev)
    .clipShape(RoundedRectangle(cornerRadius: KLTokens.radiusCard))
    .padding()
    .background(KLTokens.bg)
}
