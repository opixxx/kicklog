import SwiftUI
import SwiftData

// 경기 탭 — SwiftData @Query 로 실제 Match 표시.
// 라벨링 대기 = labeledAt == nil, 최근 경기 = labeledAt != nil 정렬 by playedAt desc.
struct MatchesScreen: View {
    @Environment(\.colorScheme) private var scheme

    // ADR-0004 — 라벨링 대기 큐: labeledAt 이 nil 인 Match (최신순)
    @Query(
        filter: #Predicate<Match> { $0.labeledAt == nil },
        sort: \Match.playedAt, order: .reverse
    )
    private var pendingMatches: [Match]

    // 라벨링 완료된 경기 (최근순)
    @Query(
        filter: #Predicate<Match> { $0.labeledAt != nil },
        sort: \Match.playedAt, order: .reverse
    )
    private var labeledMatches: [Match]

    @State private var labelingTarget: Match?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                navBar
                if pendingMatches.isEmpty && labeledMatches.isEmpty {
                    emptyState
                } else {
                    if !pendingMatches.isEmpty {
                        pendingSection
                    }
                    if !labeledMatches.isEmpty {
                        labeledSection
                    }
                    Color.clear.frame(height: 16)
                }
            }
        }
        .background(KLTokens.bg)
        .toolbarVisibility(.hidden, for: .navigationBar)
        .navigationDestination(for: Match.self) { match in
            MatchDetailScreen(match: match)
        }
        .sheet(item: $labelingTarget) { match in
            // 라벨링 편집 흐름은 B 묶음 (후속 PR) — 1차는 감지 결과만 안내.
            LabelingPlaceholderSheet(match: match)
        }
    }

    // MARK: - NavBar

    private var navBar: some View {
        KLNavBar(title: "경기", subtitle: navSubtitle) {
            HStack(spacing: 12) {
                KLIcon(name: "magnifyingglass", size: 22, color: KLTokens.pitch)
                KLIcon(name: "plus.circle.fill", size: 26, color: KLTokens.pitch)
            }
        }
    }

    private var navSubtitle: String {
        let total = labeledMatches.count
        guard total > 0 else { return "Apple Watch 에서 첫 경기를 기록하세요" }
        return "2026 시즌 · \(total)경기"
    }

    // MARK: - 빈 상태

    private var emptyState: some View {
        VStack(spacing: 22) {
            KLIcon(name: "soccerball.inverse", size: 92, color: KLTokens.pitch)
            VStack(spacing: 8) {
                Text("첫 경기를 기다리고 있어요")
                    .font(.system(size: 22, weight: .bold))
                    .tracking(-0.5)
                    .foregroundStyle(KLTokens.text)
                Text("Apple Watch 에서 Soccer 운동을 시작하세요.\n종료하면 자동으로 여기 나타납니다.")
                    .font(.system(size: 15))
                    .foregroundStyle(KLTokens.textSec)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .frame(maxWidth: 280)
            }
            HStack(spacing: 8) {
                KLIcon(name: "watch", size: 18, color: KLTokens.pitch)
                Text("워치 운동 → Soccer 선택")
                    .font(.system(size: 13))
                    .foregroundStyle(KLTokens.textSec)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(KLTokens.bgElev, in: Capsule())
            .klCardShadow(scheme)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
        .padding(.bottom, 80)
        .padding(.horizontal, 36)
    }

    // MARK: - 라벨링 대기 (가로 스크롤 큐)

    private var pendingSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            KLSectionTitle(text: "라벨링 필요한 경기", hasDot: true)
            Text("Apple Watch 에서 자동 감지됨 · 탭하여 시작")
                .font(.system(size: 13))
                .foregroundStyle(KLTokens.textSec)
                .padding(.horizontal, 20)
                .padding(.bottom, 10)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(pendingMatches) { match in
                        KLQueueCard(item: match.queueItem, onTap: { labelingTarget = match })
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 8)
            }
        }
    }

    // MARK: - 최근 경기

    private var labeledSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            KLSectionTitle(text: "최근 경기")
            VStack(spacing: 0) {
                ForEach(Array(labeledMatches.enumerated()), id: \.element.persistentModelID) { index, match in
                    NavigationLink(value: match) {
                        KLMatchRow(data: match.rowData, isLast: index == labeledMatches.count - 1)
                    }
                    .buttonStyle(.plain)
                }
            }
            .background(KLTokens.bgElev)
            .clipShape(RoundedRectangle(cornerRadius: KLTokens.radiusCard, style: .continuous))
            .padding(.horizontal, 16)
            .klCardShadow(scheme)
        }
    }
}

// MARK: - Match → LabelingQueueItem 표시 변환

extension Match {
    var queueItem: LabelingQueueItem {
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "ko_KR")
        dateFormatter.dateFormat = "yyyy-MM-dd (E)"
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH:mm"
        // 모든 쿼터의 시작/끝 범위
        let firstStart = quarters.map(\.startedAt).min() ?? playedAt
        let lastEnd = quarters.map(\.endedAt).max() ?? playedAt
        return LabelingQueueItem(
            date: dateFormatter.string(from: firstStart),
            time: "\(timeFormatter.string(from: firstStart)) ~ \(timeFormatter.string(from: lastEnd))",
            detectedQuarters: quarters.count
        )
    }
}

// MARK: - 라벨링 placeholder (Phase E2 에서 실제 편집 화면으로 전환)

private struct LabelingPlaceholderSheet: View {
    let match: Match
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                KLIcon(name: "checkmark", size: 56, color: KLTokens.pitch)
                Text("라벨링 화면은 곧 SwiftData 편집으로 전환됩니다")
                    .font(.system(size: 17, weight: .semibold))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(KLTokens.text)
                Text("감지된 쿼터: \(match.quarters.count)개")
                    .font(.system(size: 14).monospacedDigit())
                    .foregroundStyle(KLTokens.textSec)
                Spacer()
            }
            .padding()
            .padding(.top, 40)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("닫기") { dismiss() }
                }
            }
        }
    }
}

#Preview("Matches — empty") {
    NavigationStack { MatchesScreen() }
        .modelContainer(for: KickLogSchema.allModels, inMemory: true)
}
