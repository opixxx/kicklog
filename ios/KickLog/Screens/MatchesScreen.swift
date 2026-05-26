import SwiftUI
import SwiftData

// 경기 탭 — SwiftData @Query 로 실제 Match 표시.
// 라벨링 대기 = labeledAt == nil, 최근 경기 = labeledAt != nil 정렬 by playedAt desc.
struct MatchesScreen: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.modelContext) private var modelContext

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
    @State private var isLoadingRemote = false
    @State private var loadErrorMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                navBar
                if isLoadingRemote && pendingMatches.isEmpty && labeledMatches.isEmpty {
                    loadingState
                } else if let loadErrorMessage, pendingMatches.isEmpty && labeledMatches.isEmpty {
                    errorState(loadErrorMessage)
                } else if pendingMatches.isEmpty && labeledMatches.isEmpty {
                    emptyState
                } else {
                    if let loadErrorMessage {
                        inlineError(loadErrorMessage)
                    }
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
            LabelingScreen(match: match)
        }
        .task {
            await loadRemoteMatches()
        }
        .refreshable {
            await loadRemoteMatches()
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

    private var loadingState: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("경기 목록 불러오는 중…")
                .font(.system(size: 13))
                .foregroundStyle(KLTokens.textSec)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
        .padding(.bottom, 80)
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: 12) {
            KLIcon(name: "exclamationmark.triangle.fill", size: 36, color: KLTokens.amber)
            Text("경기 목록을 불러올 수 없어요")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(KLTokens.text)
            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(KLTokens.textSec)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Button("다시 시도") {
                Task { await loadRemoteMatches() }
            }
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(KLTokens.pitch)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
        .padding(.bottom, 80)
    }

    private func inlineError(_ message: String) -> some View {
        HStack(spacing: 8) {
            KLIcon(name: "exclamationmark.triangle.fill", size: 16, color: KLTokens.amber)
            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(KLTokens.textSec)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(KLTokens.bgElev, in: RoundedRectangle(cornerRadius: KLTokens.radiusCard))
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
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

    // MARK: - 서버 목록 동기화

    private func loadRemoteMatches() async {
        guard AuthTokenStore.shared.isAuthenticated else { return }
        isLoadingRemote = true
        loadErrorMessage = nil
        defer { isLoadingRemote = false }
        do {
            _ = try await MatchSyncService.shared.fetchMatches(size: 50, into: modelContext)
        } catch {
            loadErrorMessage = friendlyMessage(error)
        }
    }

    private func friendlyMessage(_ error: Error) -> String {
        if let apiError = error as? APIError {
            switch apiError {
            case .noConnection: return "네트워크 연결을 확인해 주세요"
            case .unauthorized: return "로그인이 만료되었습니다"
            case .server(_, let body, _): return body?.message ?? "서버 오류가 발생했습니다"
            case .decodingFailed: return "응답을 처리하지 못했습니다"
            case .unknown: return "알 수 없는 오류가 발생했습니다"
            }
        }
        return error.localizedDescription
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

#Preview("Matches — empty") {
    NavigationStack { MatchesScreen() }
        .modelContainer(for: KickLogSchema.allModels, inMemory: true)
}
