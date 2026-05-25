import SwiftUI

// 시즌 탭 — 연도 선택 + 6개 통계 카드 그리드 + 월별 라인 차트.
// ADR-0004 D9 — 백엔드 derive. 매번 fetch (오프라인 시 표시 불가).
struct SeasonScreen: View {
    @State private var selectedYear: Int = Calendar.current.component(.year, from: .now)
    private let years: [Int] = {
        let current = Calendar.current.component(.year, from: .now)
        return (current - 3...current).reversed().map { $0 }
    }()

    @State private var loadState: LoadState = .loading
    enum LoadState {
        case loading
        case data(SeasonStatResponse)
        case error(String)
        case unauthenticated
    }

    // 월별 라인 차트는 별도 endpoint 없음 — 1차는 빈 차트 / 후속 backend 추가 시 연결
    private let monthlyDistance: [Double] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                KLNavBar(title: "시즌") {
                    KLIcon(name: "chart.line.uptrend", size: 22, color: KLTokens.pitch)
                }

                yearPicker

                switch loadState {
                case .loading:
                    loadingView
                case .error(let message):
                    errorView(message)
                case .unauthenticated:
                    unauthenticatedView
                case .data(let stats):
                    seasonHeader(stats: stats)
                    statsGrid(stats: stats)
                    monthlyChart
                    footer
                }
            }
        }
        .background(KLTokens.bg)
        .toolbarVisibility(.hidden, for: .navigationBar)
        .task(id: selectedYear) {
            await loadSeason()
        }
        .refreshable {
            await loadSeason()
        }
    }

    // MARK: - 로드

    private func loadSeason() async {
        guard AuthTokenStore.shared.isAuthenticated else {
            loadState = .unauthenticated
            return
        }
        loadState = .loading
        do {
            let stats = try await SeasonStatService.shared.fetchMine(year: selectedYear)
            loadState = .data(stats)
        } catch let error as APIError {
            if case .unauthorized = error {
                loadState = .unauthenticated
            } else {
                loadState = .error(error.localizedDescription)
            }
        } catch {
            loadState = .error(error.localizedDescription)
        }
    }

    // MARK: - 상태 View

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("시즌 통계 불러오는 중…")
                .font(.system(size: 13))
                .foregroundStyle(KLTokens.textSec)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 12) {
            KLIcon(name: "exclamationmark.triangle.fill", size: 36, color: KLTokens.amber)
            Text("시즌 통계를 불러올 수 없어요")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(KLTokens.text)
            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(KLTokens.textSec)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Text("아래로 당겨 새로고침")
                .font(.system(size: 12))
                .foregroundStyle(KLTokens.textTer)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }

    private var unauthenticatedView: some View {
        VStack(spacing: 12) {
            KLIcon(name: "person.crop.circle.fill", size: 48, color: KLTokens.textTer)
            Text("로그인이 필요합니다")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(KLTokens.text)
            Text("설정 → 로그인 후 시즌 통계를 볼 수 있어요")
                .font(.system(size: 13))
                .foregroundStyle(KLTokens.textSec)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }

    // MARK: - 연도 선택 (가로 스크롤 + 활성 인디케이터)

    private var yearPicker: some View {
        VStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(years, id: \.self) { year in
                        let isOn = year == selectedYear
                        VStack(spacing: 2) {
                            Text(String(year))
                                .font(KLFont.numeric(17, weight: isOn ? .bold : .medium))
                                .tracking(-0.3)
                                .foregroundStyle(isOn ? KLTokens.pitch : KLTokens.textSec)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                            Rectangle()
                                .fill(isOn ? KLTokens.pitch : Color.clear)
                                .frame(height: 3)
                                .clipShape(Capsule())
                                .padding(.horizontal, 8)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { selectedYear = year }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 4)
            }
            Divider()
                .background(KLTokens.sep)
        }
        .padding(.bottom, 14)
    }

    // MARK: - 시즌 헤더

    private func seasonHeader(stats: SeasonStatResponse) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(stats.year)")
                .font(KLFont.numeric(26, weight: .bold))
                .tracking(-0.7)
                .foregroundStyle(KLTokens.text)
            Text("시즌")
                .font(.system(size: 20, weight: .bold))
                .tracking(-0.4)
                .foregroundStyle(KLTokens.text)
            Spacer()
            (Text("\(stats.matchCount)").monospacedDigit() + Text("경기 · ") + Text("\(stats.quarterCount)").monospacedDigit() + Text("쿼터"))
                .font(.system(size: 13))
                .foregroundStyle(KLTokens.textSec)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 14)
    }

    // MARK: - 2×2 통계 그리드 (api-spec §8.1 매핑 가능한 4개)
    // 승무패/평균/월별 차트는 backend Season schema 확장 후 추가 (api-spec.md TODO)

    private func statsGrid(stats: SeasonStatResponse) -> some View {
        LazyVGrid(
            columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)],
            spacing: 10
        ) {
            // 1. 누적 거리
            KLSeasonCard(icon: "figure.run", title: "누적 거리") {
                bigStat(value: String(format: "%.1f", Double(stats.totalDistanceM) / 1000.0), unit: "km")
                Text("\(stats.matchCount)경기 누적")
                    .font(.system(size: 12).monospacedDigit())
                    .foregroundStyle(KLTokens.textSec)
                    .padding(.top, 8)
            }

            // 2. 골 / 어시
            KLSeasonCard(icon: "soccerball", title: "골 / 어시스트") {
                HStack(alignment: .firstTextBaseline, spacing: 14) {
                    bigStatInline(value: "\(stats.totalGoals)", suffix: "골")
                    Rectangle()
                        .fill(KLTokens.sep)
                        .frame(width: 1, height: 22)
                    bigStatInline(value: "\(stats.totalAssists)", suffix: "어시")
                }
                if stats.matchCount > 0 {
                    let perMatch = Double(stats.totalGoals) / Double(stats.matchCount)
                    (Text("경기당 ") + Text(String(format: "%.1f", perMatch)).monospacedDigit() + Text("골"))
                        .font(.system(size: 12))
                        .foregroundStyle(KLTokens.textSec)
                        .padding(.top, 8)
                }
            }

            // 3. 출전
            KLSeasonCard(icon: "calendar", title: "출전") {
                bigStat(value: "\(stats.matchCount)", unit: "경기")
                (Text("\(stats.quarterCount)").monospacedDigit() + Text(" 쿼터 출전"))
                    .font(.system(size: 12))
                    .foregroundStyle(KLTokens.textSec)
                    .padding(.top, 8)
            }

            // 4. 시즌 베스트
            KLSeasonCard(icon: "star.fill", iconColor: KLTokens.amber, title: "시즌 베스트") {
                VStack(spacing: 7) {
                    seasonBestRow(label: "최고속도",
                                  value: String(format: "%.1f", stats.best.maxSpeedKmh), unit: "km/h")
                    seasonBestRow(label: "최장 거리",
                                  value: String(format: "%.1f", Double(stats.best.longestMatchDistanceM) / 1000.0), unit: "km")
                    seasonBestRow(label: "최다 스프린트",
                                  value: "\(stats.best.mostSprintCount)", unit: "회")
                }
            }
        }
        .padding(.horizontal, 16)
    }

    // MARK: - 월별 라인 차트

    @ViewBuilder
    private var monthlyChart: some View {
        // 월별 이동거리 API 는 후속 — backend Season schema 확장 시 활성화
        if !monthlyDistance.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text("월별 이동거리")
                        .font(.system(size: 15, weight: .bold))
                        .tracking(-0.3)
                        .foregroundStyle(KLTokens.text)
                    Spacer()
                    Text("km")
                        .font(.system(size: 12))
                        .foregroundStyle(KLTokens.textSec)
                }
                MonthlyLineChart(values: monthlyDistance)
                    .frame(height: 80)
            }
            .padding(16)
            .background(KLTokens.bgElev, in: RoundedRectangle(cornerRadius: KLTokens.radiusCard))
            .padding(.horizontal, 16)
            .padding(.top, 16)
        }
    }

    private var footer: some View {
        Text("백엔드에서 집계 · 오프라인 시 표시 불가")
            .font(.system(size: 12))
            .tracking(-0.1)
            .foregroundStyle(KLTokens.textTer)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .padding(.bottom, 8)
    }

    // MARK: - 헬퍼

    private func bigStat(value: String, unit: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(value)
                .font(KLFont.numeric(36, weight: .bold))
                .tracking(-1.4)
                .foregroundStyle(KLTokens.text)
            Text(unit)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(KLTokens.textSec)
        }
    }

    private func bigStatInline(value: String, suffix: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text(value)
                .font(KLFont.numeric(30, weight: .bold))
                .tracking(-1)
                .foregroundStyle(KLTokens.text)
            Text(suffix)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(KLTokens.text)
        }
    }

    private var dash: some View {
        Text("-")
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(KLTokens.textTer)
            .padding(.horizontal, 4)
    }

    private func seasonBestRow(label: String, value: String, unit: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(KLTokens.textSec)
            Spacer()
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(KLFont.numeric(17, weight: .bold))
                    .tracking(-0.3)
                    .foregroundStyle(KLTokens.text)
                Text(unit)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(KLTokens.textSec)
            }
        }
    }
}

// MARK: - 월별 라인 차트 Path

private struct MonthlyLineChart: View {
    let values: [Double]  // 1~5월 데이터 (6~12월은 미래)

    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let h = proxy.size.height
            let totalMonths = 12
            let xStep = (w - 20) / CGFloat(totalMonths - 1)
            let maxValue: CGFloat = 10  // 5×y_max=10 기준
            let plotHeight = h - 20

            // 12개 월 점선 그리드
            ForEach(0..<totalMonths, id: \.self) { i in
                let x = 10 + CGFloat(i) * xStep
                Path { path in
                    path.move(to: CGPoint(x: x, y: 10))
                    path.addLine(to: CGPoint(x: x, y: h - 20))
                }
                .stroke(KLTokens.hair, style: StrokeStyle(lineWidth: 1, dash: [2, 3]))
            }

            // 라인
            Path { path in
                for (i, v) in values.enumerated() {
                    let x = 10 + CGFloat(i) * xStep
                    let y = (h - 20) - (CGFloat(v) / maxValue) * plotHeight
                    if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
                    else { path.addLine(to: CGPoint(x: x, y: y)) }
                }
            }
            .stroke(KLTokens.pitch, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))

            // 점
            ForEach(Array(values.enumerated()), id: \.offset) { i, v in
                let x = 10 + CGFloat(i) * xStep
                let y = (h - 20) - (CGFloat(v) / maxValue) * plotHeight
                Circle()
                    .fill(KLTokens.pitch)
                    .frame(width: 6, height: 6)
                    .position(x: x, y: y)
            }

            // X축 라벨
            ForEach(1...totalMonths, id: \.self) { month in
                let x = 10 + CGFloat(month - 1) * xStep
                Text("\(month)")
                    .font(.system(size: 9).monospacedDigit())
                    .foregroundStyle(KLTokens.textTer)
                    .position(x: x, y: h - 6)
            }
        }
    }
}

#Preview {
    NavigationStack { SeasonScreen() }
}
