import SwiftUI

// 친구 매치 상세 — GET /users/{userId}/matches/{matchId} (5.6) 실연동.
// MatchDetailScreen 과 디자인은 동일하나 SwiftData Match 가 아닌 MatchDetailResponse 기반.
// 친구가 hideHeartRate=true 면 avgHeartRate / 쿼터별 heart rate 가 null → 비공개 표시.
struct FriendMatchDetailScreen: View {
    let userId: Int64
    let matchId: Int64
    let friendName: String

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme

    @State private var match: MatchDetailResponse?
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                if let match {
                    hero(match)
                    content(match)
                } else if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, minHeight: 300)
                } else if let errorMessage {
                    errorView(errorMessage)
                }
            }
        }
        .background(KLTokens.bg)
        .toolbarVisibility(.hidden, for: .navigationBar)
        .ignoresSafeArea(edges: match == nil ? [] : .top)
        .task { await load() }
        // .refreshable 클로저는 view rebuild 시 내부 Task 가 자동 cancel 되어
        // URLSession 요청이 -999 cancelled 로 끊긴다. 새 Task 로 wrapping 해 lifetime 분리.
        .refreshable { _ = await Task { await load() }.value }
    }

    // MARK: - Hero

    private func hero(_ match: MatchDetailResponse) -> some View {
        ZStack(alignment: .topTrailing) {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Button(action: { dismiss() }) {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 16, weight: .medium))
                            Text(friendName)
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

                HStack(alignment: .bottom, spacing: 14) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("상대팀")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.white.opacity(0.7))
                        Text(match.opponent ?? "—")
                            .font(.system(size: 28, weight: .bold))
                            .tracking(-0.8)
                            .foregroundStyle(.white)
                    }
                    Spacer(minLength: 0)
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(scoreDisplay(match))
                            .font(.system(size: 22, weight: .black).monospacedDigit())
                            .tracking(-0.5)
                        Text(MatchResult.from(Self.resultCode(match.result)).rawValue)
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
                    Text(personalContributionText(match))
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

    private func personalContributionText(_ match: MatchDetailResponse) -> AttributedString {
        var s = AttributedString("본인 ")
        var goals = AttributedString("\(match.goals)")
        goals.font = .system(size: 13, weight: .bold).monospacedDigit()
        s += goals
        s += AttributedString("골 · ")
        var assists = AttributedString("\(match.assists)")
        assists.font = .system(size: 13, weight: .bold).monospacedDigit()
        s += assists
        s += AttributedString("어시")
        return s
    }

    // MARK: - Content

    private func content(_ match: MatchDetailResponse) -> some View {
        let sortedQuarters = match.quarters
            .filter { $0.quarterNumber > 0 }
            .sorted { $0.quarterNumber < $1.quarterNumber }
        let heartRateHidden = match.avgHeartRate == nil

        return VStack(alignment: .leading, spacing: 0) {
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
                               value: heartRateHidden ? "—" : "\(match.avgHeartRate ?? 0)",
                               unit: heartRateHidden ? "비공개" : "bpm")
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
                        labels: sortedQuarters.map { "Q\($0.quarterNumber)" }
                    )
                    .klCard()

                    if heartRateHidden {
                        hiddenHeartRateCard
                    } else {
                        KLBarChart(
                            title: "평균 심박", unit: "bpm",
                            values: sortedQuarters.map { Double($0.avgHeartRate ?? 0) },
                            labels: sortedQuarters.map { "Q\($0.quarterNumber)" },
                            formatValue: { String(Int($0)) }
                        )
                        .klCard()
                    }

                    KLBarChart(
                        title: "스프린트 횟수", unit: "회",
                        values: sortedQuarters.map { Double($0.sprintCount) },
                        labels: sortedQuarters.map { "Q\($0.quarterNumber)" },
                        formatValue: { String(Int($0)) }
                    )
                    .klCard()
                }
            } else {
                Text("쿼터 정보가 없습니다")
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
                KLMetaRow(key: "상대팀", value: match.opponent ?? "—")
                KLMetaRow(key: "결과") {
                    HStack(spacing: 2) {
                        Text(scoreDisplay(match)).monospacedDigit()
                        Text(MatchResult.from(Self.resultCode(match.result)).rawValue)
                    }
                }
                KLMetaRow(key: "포지션", value: positionLong(match.position))
                KLMetaRow(key: "골") { Text("\(match.goals)").monospacedDigit() }
                KLMetaRow(key: "어시스트", value: "\(match.assists)", isLast: true)
            }
            .background(KLTokens.bgElev)
            .clipShape(RoundedRectangle(cornerRadius: KLTokens.radiusCard))
            .klCardShadow(scheme)

            Color.clear.frame(height: 28)
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

    private var hiddenHeartRateCard: some View {
        HStack(spacing: 10) {
            KLIcon(name: "heart.slash.fill", size: 18, color: KLTokens.textTer)
            VStack(alignment: .leading, spacing: 2) {
                Text("평균 심박")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(KLTokens.text)
                Text("이 친구는 심박수를 비공개로 설정했습니다")
                    .font(.system(size: 12))
                    .foregroundStyle(KLTokens.textSec)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(KLTokens.bgElev, in: RoundedRectangle(cornerRadius: KLTokens.radiusCard))
    }

    // MARK: - Error

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 16) {
            HStack {
                Button(action: { dismiss() }) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 16, weight: .medium))
                        Text(friendName)
                            .font(.system(size: 15, weight: .medium))
                    }
                    .foregroundStyle(KLTokens.pitch)
                }
                .buttonStyle(.plain)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)

            Spacer()
            Text(message)
                .font(.system(size: 14))
                .foregroundStyle(KLTokens.textSec)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            Button("다시 시도") { Task { await load() } }
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(KLTokens.pitch)
            Spacer()
        }
        .frame(maxWidth: .infinity, minHeight: 360)
    }

    // MARK: - Load

    private func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            match = try await FriendService.shared.fetchFriendMatch(userId: userId, matchId: matchId)
        } catch {
            errorMessage = friendlyMessage(error)
        }
    }

    private func friendlyMessage(_ error: Error) -> String {
        if let apiError = error as? APIError {
            switch apiError {
            case .noConnection: return "네트워크 연결을 확인해 주세요"
            case .unauthorized: return "로그인이 만료되었습니다"
            case .server(_, let body, _):
                if body?.code == "FRIEND_UNAUTHORIZED" { return "친구 관계가 아니어서 경기를 볼 수 없습니다" }
                if body?.code == "MATCH_NOT_FOUND" { return "경기를 찾을 수 없습니다" }
                if body?.code == "USER_NOT_FOUND" { return "탈퇴했거나 존재하지 않는 사용자입니다" }
                return body?.message ?? "서버 오류가 발생했습니다"
            case .decodingFailed: return "응답을 처리하지 못했습니다"
            case .unknown: return "알 수 없는 오류가 발생했습니다"
            }
        }
        return error.localizedDescription
    }

    // MARK: - Derived

    private func scoreDisplay(_ match: MatchDetailResponse) -> String {
        Match.formatScore(userGoals: match.goals, opponentGoals: match.opponentGoals)
    }

    private func positionLong(_ pos: String?) -> String {
        switch pos {
        case "GK": return "골키퍼 (GK)"
        case "DF": return "수비수 (DF)"
        case "MF": return "미드필더 (MF)"
        case "FW": return "공격수 (FW)"
        default: return "—"
        }
    }

    private static func resultCode(_ wire: String?) -> String? {
        switch wire {
        case "WIN": return "W"
        case "DRAW": return "D"
        case "LOSS": return "L"
        default: return nil
        }
    }

    private static let dateTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ko_KR")
        f.dateFormat = "yyyy-MM-dd (E) HH:mm"
        return f
    }()
}

#Preview {
    NavigationStack {
        FriendMatchDetailScreen(userId: 101, matchId: 1, friendName: "김조축")
    }
}
