import SwiftUI

// 친구 상세 — 아바타 헤더 + 4개 통계 카드 + 최근 경기 리스트.
// 본인 시즌 통계와 달리 평균심박은 비공개(KickLog 정책 — heart rate 공유 안함).
// 최근 경기는 GET /users/{userId}/matches 실연동 (5.5). 통계 4종은 별도 시즌 통계 API
// 연동 전까지 더미 유지.
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

    // 더미 통계 (시즌 통계 API 연동 전까지)
    private let totalGames = 12
    private let distanceKm = 78.2
    private let goals = 9
    private let assists = 14
    private let wins = 7
    private let draws = 3
    private let losses = 2

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
            (Text("2026 시즌 · ") + Text("\(totalGames)").monospacedDigit() + Text("경기"))
                .font(.system(size: 13))
                .foregroundStyle(KLTokens.textSec)
                .padding(.top, 4)

            HStack(spacing: 4) {
                KLIcon(name: "heart.fill", size: 11, color: KLTokens.textTer)
                Text("심박수 비공개")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(KLTokens.textSec)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(KLTokens.chipBg, in: Capsule())
            .padding(.top, 12)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
        .padding(.bottom, 18)
    }

    // MARK: - 4-card grid

    private var statsGrid: some View {
        LazyVGrid(
            columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)],
            spacing: 10
        ) {
            KLSeasonCard(icon: "figure.run", title: "누적 거리") {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(String(format: "%.1f", distanceKm))
                        .font(KLFont.numeric(30, weight: .bold))
                        .tracking(-1)
                        .foregroundStyle(KLTokens.text)
                    Text("km")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(KLTokens.textSec)
                }
                (Text("\(totalGames)").monospacedDigit() + Text("경기"))
                    .font(.system(size: 12))
                    .foregroundStyle(KLTokens.textSec)
                    .padding(.top, 8)
            }

            KLSeasonCard(icon: "soccerball", title: "골 / 어시스트") {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    HStack(alignment: .firstTextBaseline, spacing: 0) {
                        Text("\(goals)")
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
                        Text("\(assists)")
                            .font(KLFont.numeric(26, weight: .bold))
                            .tracking(-0.8)
                            .foregroundStyle(KLTokens.text)
                        Text("어시")
                            .font(.system(size: 12))
                            .foregroundStyle(KLTokens.text)
                    }
                }
                (Text("경기당 ") + Text("0.8").monospacedDigit() + Text("골"))
                    .font(.system(size: 12))
                    .foregroundStyle(KLTokens.textSec)
                    .padding(.top, 8)
            }

            KLSeasonCard(icon: "trophy.fill", iconColor: KLTokens.amber, title: "승무패") {
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    Text("\(wins)")
                        .font(KLFont.numeric(26, weight: .bold))
                        .tracking(-0.8)
                        .foregroundStyle(KLTokens.winFg)
                    Text("-")
                        .foregroundStyle(KLTokens.textTer)
                        .padding(.horizontal, 4)
                    Text("\(draws)")
                        .font(KLFont.numeric(26, weight: .bold))
                        .tracking(-0.8)
                        .foregroundStyle(KLTokens.text)
                    Text("-")
                        .foregroundStyle(KLTokens.textTer)
                        .padding(.horizontal, 4)
                    Text("\(losses)")
                        .font(KLFont.numeric(26, weight: .bold))
                        .tracking(-0.8)
                        .foregroundStyle(KLTokens.loseFg)
                }
                (Text("승률 ") + Text("58%").monospacedDigit())
                    .font(.system(size: 12))
                    .foregroundStyle(KLTokens.textSec)
                    .padding(.top, 8)
            }

            KLSeasonCard(icon: "heart.fill", iconColor: KLTokens.red, title: "평균심박") {
                Text("—")
                    .font(KLFont.numeric(26, weight: .bold))
                    .tracking(-0.8)
                    .foregroundStyle(KLTokens.textTer)
                Text("비공개")
                    .font(.system(size: 12))
                    .foregroundStyle(KLTokens.textSec)
                    .padding(.top, 8)
            }
        }
        .padding(.horizontal, 16)
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
        do {
            let response = try await FriendService.shared.fetchFriendMatches(userId: friend.userId)
            matches = response.content
            nextCursor = response.nextCursor
            hasNext = response.hasNext
        } catch {
            matches = []
            nextCursor = nil
            hasNext = false
            errorMessage = friendlyMessage(error)
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
                if body?.code == "USER_NOT_FOUND" { return "탈퇴했거나 존재하지 않는 사용자입니다" }
                return body?.message ?? "서버 오류가 발생했습니다"
            case .decodingFailed: return "응답을 처리하지 못했습니다"
            case .unknown: return "알 수 없는 오류가 발생했습니다"
            }
        }
        return error.localizedDescription
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
