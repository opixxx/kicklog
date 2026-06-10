import SwiftUI

// 친구 상세 — 아바타 헤더 + 4개 통계 카드 + 최근 경기 리스트.
// 통계 4종(거리/골·어시/승무패/평균심박) 모두 GET /users/{userId}/seasons/{year} (8.2) 실연동.
// 심박 마스킹 정책 폐기 (V11 마이그레이션) — 친구는 모든 지표를 평문으로 본다.
// 최근 경기는 GET /users/{userId}/matches 실연동 (5.5).
struct FriendDetailScreen: View {
    let friend: FriendSummary
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme

    @State private var matches: [MatchSummaryResponse] = []
    @State private var nextCursor: String?
    @State private var hasNext = false
    @State private var isLoading = false
    @State private var isLoadingMore = false
    @State private var errorMessage: String?

    // 친구 시즌 통계 — 현재 연도 1년치만 표시 (디자인상 picker 없음).
    // nil = 로딩 / 실패 → 카드는 placeholder "—". 매치 로드 실패와는 독립적.
    @State private var stats: SeasonStatResponse?
    private let displayYear = Calendar.current.component(.year, from: .now)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                customNavBar
                profileHeader
                statsGrid
                recentMatchesSection
                Color.clear.frame(height: 24)
            }
        }
        .background(KLTokens.bg)
        .toolbarVisibility(.hidden, for: .navigationBar)
        .navigationDestination(for: FriendMatchTarget.self) { target in
            FriendMatchDetailScreen(userId: target.userId, matchId: target.matchId, friendName: target.friendName)
        }
        .task { await loadInitial() }
        // .refreshable 클로저는 view rebuild 시 내부 Task 가 자동 cancel 되어
        // URLSession 요청이 -999 cancelled 로 끊긴다. 새 Task 로 wrapping 해 lifetime 분리.
        .refreshable { _ = await Task { await loadInitial() }.value }
    }

    // MARK: - Custom Nav

    private var customNavBar: some View {
        HStack {
            Button(action: { dismiss() }) {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .medium))
                    Text("친구")
                        .font(.system(size: 15, weight: .medium))
                }
                .foregroundStyle(KLTokens.pitch)
            }
            .buttonStyle(.plain)
            Spacer()
            Text("···")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(KLTokens.pitch)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    // MARK: - Profile Header

    private var profileHeader: some View {
        VStack(spacing: 0) {
            KLAvatar(name: friend.displayName, size: 76)
            Text(friend.displayName)
                .font(.system(size: 22, weight: .bold))
                .tracking(-0.5)
                .foregroundStyle(KLTokens.text)
                .padding(.top, 12)
            (Text("\(String(stats?.year ?? displayYear)) 시즌 · ") + Text("\(stats?.matchCount ?? 0)").monospacedDigit() + Text("경기"))
                .font(.system(size: 13))
                .foregroundStyle(KLTokens.textSec)
                .padding(.top, 4)
                .padding(.bottom, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
        .padding(.bottom, 18)
    }

    // MARK: - 4-card grid (8.2 SeasonStatResponse 기반)
    // stats == nil 이면 숫자는 "—" placeholder.

    private var statsGrid: some View {
        LazyVGrid(
            columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)],
            spacing: 10
        ) {
            distanceCard
            goalAssistCard
            recordCard
            heartRateCard
        }
        .padding(.horizontal, 16)
    }

    private var distanceCard: some View {
        let value = stats.map { String(format: "%.1f", Double($0.totalDistanceM) / 1000.0) } ?? "—"
        let matchCount = stats?.matchCount ?? 0
        return KLSeasonCard(icon: "figure.run", title: "누적 거리") {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(KLFont.numeric(30, weight: .bold))
                    .tracking(-1)
                    .foregroundStyle(KLTokens.text)
                Text("km")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(KLTokens.textSec)
            }
            (Text("\(matchCount)").monospacedDigit() + Text("경기"))
                .font(.system(size: 12))
                .foregroundStyle(KLTokens.textSec)
                .padding(.top, 8)
        }
    }

    private var goalAssistCard: some View {
        // 경기당 골 = totalGoals / matchCount. matchCount 0 이면 숨김 (0으로 나누기 회피).
        let perMatch: Double? = {
            guard let stats, stats.matchCount > 0 else { return nil }
            return Double(stats.totalGoals) / Double(stats.matchCount)
        }()
        return KLSeasonCard(icon: "soccerball", title: "골 / 어시스트") {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    Text(stats.map { String($0.totalGoals) } ?? "—")
                        .font(KLFont.numeric(26, weight: .bold))
                        .tracking(-0.8)
                        .foregroundStyle(KLTokens.text)
                    Text("골")
                        .font(.system(size: 12))
                        .foregroundStyle(KLTokens.text)
                }
                Text("·")
                    .foregroundStyle(KLTokens.textTer)
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    Text(stats.map { String($0.totalAssists) } ?? "—")
                        .font(KLFont.numeric(26, weight: .bold))
                        .tracking(-0.8)
                        .foregroundStyle(KLTokens.text)
                    Text("어시")
                        .font(.system(size: 12))
                        .foregroundStyle(KLTokens.text)
                }
            }
            if let perMatch {
                (Text("경기당 ") + Text(String(format: "%.1f", perMatch)).monospacedDigit() + Text("골"))
                    .font(.system(size: 12))
                    .foregroundStyle(KLTokens.textSec)
                    .padding(.top, 8)
            }
        }
    }

    private var recordCard: some View {
        // 승률 = winCount / (W+D+L) * 100. 합이 0이면 숨김 (SeasonScreen winRateLabel 과 동일 규약).
        let total = (stats?.winCount ?? 0) + (stats?.drawCount ?? 0) + (stats?.lossCount ?? 0)
        let winPct: Int? = {
            guard let stats, total > 0 else { return nil }
            return Int((Double(stats.winCount) / Double(total) * 100).rounded())
        }()
        return KLSeasonCard(icon: "trophy.fill", iconColor: KLTokens.amber, title: "승무패") {
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text(stats.map { String($0.winCount) } ?? "—")
                    .font(KLFont.numeric(26, weight: .bold))
                    .tracking(-0.8)
                    .foregroundStyle(KLTokens.winFg)
                Text("-")
                    .foregroundStyle(KLTokens.textTer)
                    .padding(.horizontal, 4)
                Text(stats.map { String($0.drawCount) } ?? "—")
                    .font(KLFont.numeric(26, weight: .bold))
                    .tracking(-0.8)
                    .foregroundStyle(KLTokens.text)
                Text("-")
                    .foregroundStyle(KLTokens.textTer)
                    .padding(.horizontal, 4)
                Text(stats.map { String($0.lossCount) } ?? "—")
                    .font(KLFont.numeric(26, weight: .bold))
                    .tracking(-0.8)
                    .foregroundStyle(KLTokens.loseFg)
            }
            if let winPct {
                (Text("승률 ") + Text("\(winPct)%").monospacedDigit())
                    .font(.system(size: 12))
                    .foregroundStyle(KLTokens.textSec)
                    .padding(.top, 8)
            }
        }
    }

    // 평균심박 — SeasonStatResponse.avgHeartRate 평문 노출 (마스킹 정책 폐기 — V11).
    // stats nil 또는 avgHeartRate == 0 (측정값 없음) 이면 "—" placeholder.
    private var heartRateCard: some View {
        let value = stats?.avgHeartRate ?? 0
        let display = value > 0 ? "\(value)" : "—"
        return KLSeasonCard(icon: "heart.fill", iconColor: KLTokens.red, title: "평균심박") {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(display)
                    .font(KLFont.numeric(26, weight: .bold))
                    .tracking(-0.8)
                    .foregroundStyle(value > 0 ? KLTokens.text : KLTokens.textTer)
                Text("bpm")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(KLTokens.textSec)
            }
            Text("시즌 평균")
                .font(.system(size: 12))
                .foregroundStyle(KLTokens.textSec)
                .padding(.top, 8)
        }
    }

    // MARK: - 최근 경기 (실연동)

    private var recentMatchesSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("최근 경기")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(KLTokens.textSec)
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 8)

            recentMatchesContent
        }
    }

    @ViewBuilder
    private var recentMatchesContent: some View {
        if isLoading && matches.isEmpty {
            ProgressView()
                .frame(maxWidth: .infinity, minHeight: 80)
        } else if let errorMessage, matches.isEmpty {
            VStack(spacing: 8) {
                Text(errorMessage)
                    .font(.system(size: 13))
                    .foregroundStyle(KLTokens.textSec)
                    .multilineTextAlignment(.center)
                Button("다시 시도") { Task { await loadInitial() } }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(KLTokens.pitch)
            }
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, minHeight: 80)
            .background(KLTokens.bgElev, in: RoundedRectangle(cornerRadius: KLTokens.radiusCard))
            .padding(.horizontal, 16)
        } else if matches.isEmpty {
            Text("아직 경기 기록이 없습니다")
                .font(.system(size: 13))
                .foregroundStyle(KLTokens.textSec)
                .frame(maxWidth: .infinity, minHeight: 80)
                .background(KLTokens.bgElev, in: RoundedRectangle(cornerRadius: KLTokens.radiusCard))
                .padding(.horizontal, 16)
        } else {
            VStack(spacing: 0) {
                ForEach(Array(matches.enumerated()), id: \.element.id) { index, match in
                    NavigationLink(
                        value: FriendMatchTarget(
                            userId: friend.userId,
                            matchId: match.id,
                            friendName: friend.displayName
                        )
                    ) {
                        compactMatchRow(match, isLast: index == matches.count - 1 && !hasNext)
                    }
                    .buttonStyle(.plain)
                }

                if hasNext {
                    loadMoreFooter
                }
            }
            .background(KLTokens.bgElev)
            .clipShape(RoundedRectangle(cornerRadius: KLTokens.radiusCard))
            .padding(.horizontal, 16)
            .klCardShadow(scheme)
        }
    }

    // 마지막 행 직후 sentinel — 화면에 들어오면 다음 페이지 로딩 트리거.
    // errorMessage 가 있고 matches 가 비어있지 않으면(= 추가 페이지 실패) "다시 시도" 노출.
    private var loadMoreFooter: some View {
        Group {
            if let errorMessage, !isLoadingMore {
                VStack(spacing: 6) {
                    Text(errorMessage)
                        .font(.system(size: 12))
                        .foregroundStyle(KLTokens.textSec)
                        .multilineTextAlignment(.center)
                    Button("다시 시도") { Task { await loadMore() } }
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(KLTokens.pitch)
                }
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity)
            } else {
                ProgressView()
                    .padding(.vertical, 14)
                    .frame(maxWidth: .infinity)
                    .task { await loadMore() }
            }
        }
    }

    private func compactMatchRow(_ match: MatchSummaryResponse, isLast: Bool) -> some View {
        let result = MatchResult.from(matchResultCode(from: match.result))
        let score = Match.formatScore(teamGoals: match.teamGoals, opponentGoals: match.opponentGoals, fallbackUserGoals: match.goals)
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text(Self.dateNumFormatter.string(from: match.playedAt))
                    .font(KLFont.numeric(19, weight: .bold))
                    .tracking(-0.4)
                    .foregroundStyle(KLTokens.text)
                Text(Self.dowFormatter.string(from: match.playedAt))
                    .font(.system(size: 11))
                    .foregroundStyle(KLTokens.textSec)
            }
            .frame(minWidth: 38, alignment: .leading)

            VStack(alignment: .leading, spacing: 1) {
                Text(match.opponent ?? "—")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(KLTokens.text)
                Text(quarterLabel(match.quarterCount))
                    .font(.system(size: 12))
                    .foregroundStyle(KLTokens.textSec)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            KLChip(bg: resultBg(result), fg: resultFg(result), size: .sm) {
                Text(score).monospacedDigit()
                Text(result.rawValue).padding(.leading, 2)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .overlay(alignment: .bottom) {
            if !isLast {
                Rectangle()
                    .fill(KLTokens.sep)
                    .frame(height: 0.5)
                    .padding(.leading, 16)
            }
        }
    }

    private func quarterLabel(_ count: Int) -> String {
        count > 0 ? "\(count)쿼터 출전" : "쿼터 정보 없음"
    }

    private func matchResultCode(from wire: String?) -> String? {
        switch wire {
        case "WIN": return "W"
        case "DRAW": return "D"
        case "LOSS": return "L"
        default: return nil
        }
    }

    private func resultBg(_ r: MatchResult) -> Color {
        switch r { case .win: return KLTokens.winBg; case .draw: return KLTokens.drawBg; case .lose: return KLTokens.loseBg }
    }
    private func resultFg(_ r: MatchResult) -> Color {
        switch r { case .win: return KLTokens.winFg; case .draw: return KLTokens.drawFg; case .lose: return KLTokens.loseFg }
    }

    // MARK: - Load

    private func loadInitial() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        // 시즌 통계와 최근 경기 병렬 fetch. 통계 실패는 placeholder "—" 유지(매치 영역과 독립).
        async let matchesTask = FriendService.shared.fetchFriendMatches(userId: friend.userId)
        async let statsTask = SeasonStatService.shared.fetchFriend(userId: friend.userId, year: displayYear)

        stats = try? await statsTask

        do {
            let response = try await matchesTask
            matches = response.content
            nextCursor = response.nextCursor
            hasNext = response.hasNext
        } catch {
            matches = []
            nextCursor = nil
            hasNext = false
            errorMessage = error.userMessage(serverCodes: [
                "FRIEND_UNAUTHORIZED": "친구 관계가 아니어서 경기를 볼 수 없습니다",
                "USER_NOT_FOUND": "탈퇴했거나 존재하지 않는 사용자입니다",
            ])
        }
    }

    // 무한 스크롤 — sentinel(loadMoreFooter)의 .task 에서 호출.
    // SwiftUI 가 같은 sentinel View 를 재사용할 수 있어 중복 호출 방지를 위해
    // isLoadingMore 가드 + hasNext / nextCursor 체크.
    private func loadMore() async {
        guard !isLoadingMore, hasNext, let cursor = nextCursor else { return }
        isLoadingMore = true
        errorMessage = nil
        defer { isLoadingMore = false }
        do {
            let response = try await FriendService.shared.fetchFriendMatches(
                userId: friend.userId,
                cursor: cursor
            )
            // 중복 방지 — 동일 id 가 들어오면 append 하지 않음 (방어적)
            let existingIds = Set(matches.map(\.id))
            matches.append(contentsOf: response.content.filter { !existingIds.contains($0.id) })
            nextCursor = response.nextCursor
            hasNext = response.hasNext
        } catch {
            errorMessage = error.userMessage(serverCodes: [
                "FRIEND_UNAUTHORIZED": "친구 관계가 아니어서 경기를 볼 수 없습니다",
                "USER_NOT_FOUND": "탈퇴했거나 존재하지 않는 사용자입니다",
            ])
        }
    }


    // MARK: - Formatters

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

// MARK: - Navigation 타겟

struct FriendMatchTarget: Hashable {
    let userId: Int64
    let matchId: Int64
    let friendName: String
}

#Preview {
    NavigationStack {
        FriendDetailScreen(friend: FriendSummary.previewSamples[1])
    }
}
