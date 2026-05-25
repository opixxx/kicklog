import SwiftUI
import SwiftData

// 매치 상세 — SwiftData Match 기반.
// Hero (pitch 그라디언트) → 2×2 통계 → 쿼터별 막대 차트 3개 → 메타 정보 → 카카오 공유.
struct MatchDetailScreen: View {
    let match: Match
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme

    // 라벨링된 쿼터만, quarterNo 오름차순
    private var sortedQuarters: [QuarterWorkout] {
        match.quarters.filter { $0.quarterNo > 0 }.sorted { $0.quarterNo < $1.quarterNo }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                hero
                content
            }
        }
        .background(KLTokens.bg)
        .toolbarVisibility(.hidden, for: .navigationBar)
        .ignoresSafeArea(edges: .top)
    }

    // MARK: - Hero

    private var hero: some View {
        ZStack(alignment: .topTrailing) {
            HeroPitchDecoration()
                .stroke(Color.white.opacity(0.08), lineWidth: 1.5)
                .frame(width: 280, height: 280)
                .offset(x: 60, y: 30)

            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Button(action: { dismiss() }) {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 16, weight: .medium))
                            Text("경기")
                                .font(.system(size: 15, weight: .medium))
                        }
                        .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                    Spacer()
                    Text("···")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.85))
                }
                .frame(minHeight: 36)
                .padding(.bottom, 18)

                Text(Self.dateTimeFormatter.string(from: match.playedAt))
                    .font(.system(size: 13, weight: .medium).monospacedDigit())
                    .tracking(-0.2)
                    .foregroundStyle(.white.opacity(0.85))
                Text(venueDisplay)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(.top, 2)

                HStack(alignment: .bottom, spacing: 14) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("상대팀")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.white.opacity(0.7))
                        Text(match.opponentName ?? "—")
                            .font(.system(size: 28, weight: .bold))
                            .tracking(-0.8)
                            .foregroundStyle(.white)
                    }
                    Spacer(minLength: 0)
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(scoreDisplay)
                            .font(.system(size: 22, weight: .black).monospacedDigit())
                            .tracking(-0.5)
                        Text(MatchResult.from(match.result).rawValue)
                            .font(.system(size: 15, weight: .bold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(.white.opacity(0.18), in: Capsule())
                    .overlay(Capsule().stroke(.white.opacity(0.25), lineWidth: 1))
                }
                .padding(.top, 18)

                HStack(spacing: 8) {
                    Text(match.position ?? "—")
                        .font(.system(size: 12, weight: .bold))
                        .tracking(0.4)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(.black.opacity(0.25), in: Capsule())
                    Text(personalContributionText)
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.9))
                }
                .padding(.top, 14)
            }
            .padding(.horizontal, 20)
            .padding(.top, 60)
            .padding(.bottom, 44)
        }
        .background(
            LinearGradient(
                colors: [KLTokens.pitch, KLTokens.pitchDeep, Color(hex: 0x0A2D0D)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipped()
    }

    private var personalContributionText: AttributedString {
        var s = AttributedString("본인 ")
        var goals = AttributedString("\(match.userGoals ?? 0)")
        goals.font = .system(size: 13, weight: .bold).monospacedDigit()
        s += goals
        s += AttributedString("골 · ")
        var assists = AttributedString("\(match.userAssists ?? 0)")
        assists.font = .system(size: 13, weight: .bold).monospacedDigit()
        s += assists
        s += AttributedString("어시")
        return s
    }

    // MARK: - Content (둥근 모서리 영역)

    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)],
                spacing: 10
            ) {
                KLStatCardMini(icon: "figure.run", label: "이동거리",
                               value: String(format: "%.1f", Double(match.totalDistanceM) / 1000.0), unit: "km")
                KLStatCardMini(icon: "speedometer", label: "최고속도",
                               value: String(format: "%.1f", match.maxSpeedKmh), unit: "km/h")
                KLStatCardMini(icon: "bolt.fill", iconColor: KLTokens.amber, label: "스프린트",
                               value: "\(match.sprintCount)", unit: "회")
                KLStatCardMini(icon: "heart.fill", iconColor: KLTokens.red, label: "평균심박",
                               value: "\(match.avgHeartRate)", unit: "bpm")
            }

            HStack(alignment: .firstTextBaseline) {
                Text("쿼터별 분석")
                    .font(KLFont.sectionTitle())
                    .tracking(-0.5)
                    .foregroundStyle(KLTokens.text)
                Spacer()
                Text("\(sortedQuarters.count)쿼터 출전")
                    .font(.system(size: 12).monospacedDigit())
                    .foregroundStyle(KLTokens.textSec)
            }
            .padding(.top, 24)
            .padding(.bottom, 10)

            if !sortedQuarters.isEmpty {
                VStack(spacing: 10) {
                    KLBarChart(
                        title: "평균 속도", unit: "km/h",
                        values: sortedQuarters.map(\.avgSpeedKmh),
                        labels: quarterLabels
                    )
                    .klCard()

                    KLBarChart(
                        title: "평균 심박", unit: "bpm",
                        values: sortedQuarters.map { Double($0.avgHeartRate) },
                        labels: quarterLabels,
                        formatValue: { String(Int($0)) }
                    )
                    .klCard()

                    KLBarChart(
                        title: "스프린트 횟수", unit: "회",
                        values: sortedQuarters.map { Double($0.sprintCount) },
                        labels: quarterLabels,
                        formatValue: { String(Int($0)) }
                    )
                    .klCard()
                }
            } else {
                Text("아직 쿼터 라벨링이 되지 않았습니다")
                    .font(.system(size: 13))
                    .foregroundStyle(KLTokens.textSec)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
            }

            Text("상세 정보")
                .font(KLFont.sectionTitle())
                .tracking(-0.5)
                .foregroundStyle(KLTokens.text)
                .padding(.top, 24)
                .padding(.bottom, 10)

            VStack(spacing: 0) {
                KLMetaRow(key: "상대팀", value: match.opponentName ?? "—")
                KLMetaRow(key: "결과") {
                    HStack(spacing: 2) {
                        Text(scoreDisplay).monospacedDigit()
                        Text(MatchResult.from(match.result).rawValue)
                    }
                }
                KLMetaRow(key: "포지션", value: positionLong)
                KLMetaRow(key: "골") {
                    Text("\(match.userGoals ?? 0)").monospacedDigit()
                }
                KLMetaRow(key: "어시스트") {
                    Text("\(match.userAssists ?? 0)").monospacedDigit()
                }
                KLMetaRow(key: "운동장", value: venueDisplay, isLast: true)
            }
            .background(KLTokens.bgElev)
            .clipShape(RoundedRectangle(cornerRadius: KLTokens.radiusCard))
            .klCardShadow(scheme)

            Button(action: {}) {
                HStack(spacing: 8) {
                    KLIcon(name: "kakao.bubble", size: 20, color: Color(hex: 0x3C1E1E))
                    Text("카카오톡으로 공유")
                        .font(.system(size: 16, weight: .bold))
                        .tracking(-0.3)
                        .foregroundStyle(Color(hex: 0x3C1E1E))
                }
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(Color(hex: 0xFEE500), in: RoundedRectangle(cornerRadius: KLTokens.radiusBtn))
            }
            .buttonStyle(.plain)
            .padding(.top, 22)
            .padding(.bottom, 14)
        }
        .padding(.horizontal, 16)
        .padding(.top, 20)
        .background(
            UnevenRoundedRectangle(
                topLeadingRadius: 24,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 0,
                topTrailingRadius: 24
            )
            .fill(KLTokens.bg)
        )
        .offset(y: -28)
    }

    // MARK: - Derived display

    private var quarterLabels: [String] {
        sortedQuarters.map { "Q\($0.quarterNo)" }
    }

    private var venueDisplay: String {
        // venueId → Venue.name 조회는 C 묶음에서 도입. 1차 placeholder.
        "—"
    }

    private var scoreDisplay: String {
        Match.formatScore(userGoals: match.userGoals, opponentGoals: match.opponentGoals)
    }

    private var positionLong: String {
        switch match.position {
        case "GK": return "골키퍼 (GK)"
        case "DF": return "수비수 (DF)"
        case "MF": return "미드필더 (MF)"
        case "FW": return "공격수 (FW)"
        default: return "—"
        }
    }

    // MARK: - Formatters

    private static let dateTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ko_KR")
        f.dateFormat = "yyyy-MM-dd (E) HH:mm"
        return f
    }()
}

// MARK: - Hero 의 큰 축구장 데코

private struct HeroPitchDecoration: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let scaleX = rect.width / 280
        let scaleY = rect.height / 280
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * scaleX, y: rect.minY + y * scaleY)
        }

        path.addRoundedRect(
            in: CGRect(
                x: rect.minX + 10 * scaleX, y: rect.minY + 10 * scaleY,
                width: 260 * scaleX, height: 260 * scaleY
            ),
            cornerSize: CGSize(width: 4 * scaleX, height: 4 * scaleY)
        )
        path.move(to: p(10, 140))
        path.addLine(to: p(270, 140))
        path.addEllipse(in: CGRect(
            x: rect.minX + (140 - 40) * scaleX,
            y: rect.minY + (140 - 40) * scaleY,
            width: 80 * scaleX, height: 80 * scaleY
        ))
        path.addRect(CGRect(
            x: rect.minX + 10 * scaleX, y: rect.minY + 80 * scaleY,
            width: 50 * scaleX, height: 120 * scaleY
        ))
        path.addRect(CGRect(
            x: rect.minX + 220 * scaleX, y: rect.minY + 80 * scaleY,
            width: 50 * scaleX, height: 120 * scaleY
        ))
        return path
    }
}
