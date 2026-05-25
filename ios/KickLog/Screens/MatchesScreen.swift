import SwiftUI

// 경기 탭 — 라벨링 큐 가로 스크롤 + 최근 경기 리스트.
// JSX matches.jsx 와 동일 구조.
struct MatchesScreen: View {
    @Environment(\.colorScheme) private var scheme
    @State private var queue: [LabelingQueueItem] = LabelingQueueItem.samples
    @State private var matches: [Match] = Match.samples
    @State private var labelingTarget: LabelingQueueItem?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                KLNavBar(title: "경기", subtitle: "2026 시즌 · \(matches.count)경기") {
                    HStack(spacing: 12) {
                        KLIcon(name: "magnifyingglass", size: 22, color: KLTokens.pitch)
                        KLIcon(name: "plus.circle.fill", size: 26, color: KLTokens.pitch)
                    }
                }

                // 라벨링 큐 섹션
                KLSectionTitle(text: "라벨링 필요한 경기", hasDot: true)
                Text("Apple Watch에서 자동 감지됨 · 탭하여 시작")
                    .font(.system(size: 13))
                    .foregroundStyle(KLTokens.textSec)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 10)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(queue) { item in
                            KLQueueCard(item: item, onTap: { labelingTarget = item })
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)
                }

                // 최근 경기 섹션
                KLSectionTitle(text: "최근 경기")
                VStack(spacing: 0) {
                    ForEach(Array(matches.enumerated()), id: \.element.id) { index, match in
                        NavigationLink(value: match) {
                            KLMatchRow(match: match, isLast: index == matches.count - 1)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .background(KLTokens.bgElev)
                .clipShape(RoundedRectangle(cornerRadius: KLTokens.radiusCard, style: .continuous))
                .padding(.horizontal, 16)
                .klCardShadow(scheme)

                Color.clear.frame(height: 16)
            }
        }
        .background(KLTokens.bg)
        .toolbarVisibility(.hidden, for: .navigationBar)
        .navigationDestination(for: Match.self) { match in
            MatchDetailScreen(match: match)
        }
        .sheet(item: $labelingTarget) { item in
            LabelingScreen(item: item)
        }
    }
}

#Preview("Matches — Light") {
    NavigationStack { MatchesScreen() }
}

#Preview("Matches — Dark") {
    NavigationStack { MatchesScreen() }
        .preferredColorScheme(.dark)
}
