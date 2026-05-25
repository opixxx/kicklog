import SwiftUI

// 친구 상세 — 아바타 헤더 + 4개 통계 카드 + 최근 경기 리스트.
// 본인 시즌 통계와 달리 평균심박은 비공개(KickLog 정책 — heart rate 공유 안함).
// E4: friend 시그니처를 도메인 모델 Friend 로 교체. 통계/최근경기 실연동은 후속 단계.
struct FriendDetailScreen: View {
    let friend: Friend
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme

    // 더미 통계 (실제로는 백엔드에서 가져옴 — 후속 단계)
    private let totalGames = 12
    private let distanceKm = 78.2
    private let goals = 9
    private let assists = 14
    private let wins = 7
    private let draws = 3
    private let losses = 2

    private let recentMatches: [SampleMatch] = Array(SampleMatch.samples.prefix(2))

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
            KLAvatar(name: friend.name, size: 76)
            Text(friend.name)
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

    // MARK: - 최근 경기

    private var recentMatchesSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("최근 경기")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(KLTokens.textSec)
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 8)

            VStack(spacing: 0) {
                ForEach(Array(recentMatches.enumerated()), id: \.element.id) { index, match in
                    compactMatchRow(match, isLast: index == recentMatches.count - 1)
                }
            }
            .background(KLTokens.bgElev)
            .clipShape(RoundedRectangle(cornerRadius: KLTokens.radiusCard))
            .padding(.horizontal, 16)
            .klCardShadow(scheme)
        }
    }

    private func compactMatchRow(_ match: SampleMatch, isLast: Bool) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text(match.dateNum)
                    .font(KLFont.numeric(19, weight: .bold))
                    .tracking(-0.4)
                    .foregroundStyle(KLTokens.text)
                Text(match.dow)
                    .font(.system(size: 11))
                    .foregroundStyle(KLTokens.textSec)
            }
            .frame(minWidth: 38, alignment: .leading)

            VStack(alignment: .leading, spacing: 1) {
                Text(match.opponent)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(KLTokens.text)
                Text(match.venue)
                    .font(.system(size: 12))
                    .foregroundStyle(KLTokens.textSec)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            KLChip(bg: resultBg(match.result), fg: resultFg(match.result), size: .sm) {
                Text(match.score).monospacedDigit()
                Text(match.result.rawValue).padding(.leading, 2)
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

    private func resultBg(_ r: MatchResult) -> Color {
        switch r { case .win: return KLTokens.winBg; case .draw: return KLTokens.drawBg; case .lose: return KLTokens.loseBg }
    }
    private func resultFg(_ r: MatchResult) -> Color {
        switch r { case .win: return KLTokens.winFg; case .draw: return KLTokens.drawFg; case .lose: return KLTokens.loseFg }
    }
}

#Preview {
    NavigationStack {
        FriendDetailScreen(friend: Friend.previewSamples[1])
    }
}
