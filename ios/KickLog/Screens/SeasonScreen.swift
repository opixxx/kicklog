import SwiftUI

// 시즌 탭 — 연도 선택 + 6개 통계 카드 그리드 + 월별 라인 차트.
// JSX season.jsx 와 동일 구조.
struct SeasonScreen: View {
    @State private var selectedYear: String = "2026"
    private let years = ["2026", "2025", "2024", "2023"]

    // 더미 시즌 데이터 (와이어프레임 하드코딩 값)
    private let totalGames = 14
    private let totalQuarters = 47
    private let totalDistanceKm = 95.4
    private let goals = 18
    private let assists = 11
    private let wins = 8
    private let draws = 3
    private let losses = 3
    private let bestSpeedKmh = 29.4
    private let bestDistanceKm = 8.2
    private let bestSprintCount = 21
    private let avgDistanceKm = 6.8
    private let avgHeartRateBpm = 152
    private let monthlyDistance: [Double] = [4.8, 6.2, 7.4, 8.1, 9.0]  // 1~5월

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                KLNavBar(title: "시즌") {
                    KLIcon(name: "chart.line.uptrend", size: 22, color: KLTokens.pitch)
                }

                yearPicker
                seasonHeader
                statsGrid
                monthlyChart
                footer
            }
        }
        .background(KLTokens.bg)
        .toolbarVisibility(.hidden, for: .navigationBar)
    }

    // MARK: - 연도 선택 (가로 스크롤 + 활성 인디케이터)

    private var yearPicker: some View {
        VStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(years, id: \.self) { year in
                        let isOn = year == selectedYear
                        VStack(spacing: 2) {
                            Text(year)
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

    private var seasonHeader: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(selectedYear)
                .font(KLFont.numeric(26, weight: .bold))
                .tracking(-0.7)
                .foregroundStyle(KLTokens.text)
            Text("시즌")
                .font(.system(size: 20, weight: .bold))
                .tracking(-0.4)
                .foregroundStyle(KLTokens.text)
            Spacer()
            (Text("\(totalGames)").monospacedDigit() + Text("경기 · ") + Text("\(totalQuarters)").monospacedDigit() + Text("쿼터"))
                .font(.system(size: 13))
                .foregroundStyle(KLTokens.textSec)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 14)
    }

    // MARK: - 2×3 통계 그리드

    private var statsGrid: some View {
        LazyVGrid(
            columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)],
            spacing: 10
        ) {
            // 1. 누적 거리
            KLSeasonCard(icon: "figure.run", title: "누적 거리") {
                bigStat(value: String(format: "%.1f", totalDistanceKm), unit: "km")
                Text("\(totalGames)경기 누적")
                    .font(.system(size: 12).monospacedDigit())
                    .foregroundStyle(KLTokens.textSec)
                    .padding(.top, 8)
            }

            // 2. 골 / 어시
            KLSeasonCard(icon: "soccerball", title: "골 / 어시스트") {
                HStack(alignment: .firstTextBaseline, spacing: 14) {
                    bigStatInline(value: "\(goals)", suffix: "골")
                    Rectangle()
                        .fill(KLTokens.sep)
                        .frame(width: 1, height: 22)
                    bigStatInline(value: "\(assists)", suffix: "어시")
                }
                (Text("경기당 ") + Text("1.3").monospacedDigit() + Text("골"))
                    .font(.system(size: 12))
                    .foregroundStyle(KLTokens.textSec)
                    .padding(.top, 8)
            }

            // 3. 승무패
            KLSeasonCard(icon: "trophy.fill", iconColor: KLTokens.amber, title: "승무패") {
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    Text("\(wins)")
                        .font(KLFont.numeric(30, weight: .bold))
                        .tracking(-1)
                        .foregroundStyle(KLTokens.winFg)
                    dash
                    Text("\(draws)")
                        .font(KLFont.numeric(30, weight: .bold))
                        .tracking(-1)
                        .foregroundStyle(KLTokens.text)
                    dash
                    Text("\(losses)")
                        .font(KLFont.numeric(30, weight: .bold))
                        .tracking(-1)
                        .foregroundStyle(KLTokens.loseFg)
                }
                (Text("승률 ") + Text("57%").font(.system(size: 12, weight: .bold)).foregroundColor(KLTokens.text))
                    .font(.system(size: 12).monospacedDigit())
                    .foregroundStyle(KLTokens.textSec)
                    .padding(.top, 8)
            }

            // 4. 시즌 베스트
            KLSeasonCard(icon: "star.fill", iconColor: KLTokens.amber, title: "시즌 베스트") {
                VStack(spacing: 7) {
                    seasonBestRow(label: "최고속도", value: String(format: "%.1f", bestSpeedKmh), unit: "km/h")
                    seasonBestRow(label: "최장 거리", value: String(format: "%.1f", bestDistanceKm), unit: "km")
                    seasonBestRow(label: "최다 스프린트", value: "\(bestSprintCount)", unit: "회")
                }
            }

            // 5. 출전
            KLSeasonCard(icon: "calendar", title: "출전") {
                bigStat(value: "\(totalGames)", unit: "경기")
                (Text("\(totalQuarters)").monospacedDigit() + Text(" 쿼터 출전"))
                    .font(.system(size: 12))
                    .foregroundStyle(KLTokens.textSec)
                    .padding(.top, 8)
            }

            // 6. 평균
            KLSeasonCard(icon: "chart.line.uptrend", title: "평균") {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(String(format: "%.1f", avgDistanceKm))
                        .font(KLFont.numeric(26, weight: .bold))
                        .tracking(-0.9)
                        .foregroundStyle(KLTokens.text)
                    Text("km / 경기")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(KLTokens.textSec)
                }
                (Text("평균심박 ") + Text("\(avgHeartRateBpm)").font(.system(size: 12, weight: .bold)).foregroundColor(KLTokens.text) + Text(" bpm"))
                    .font(.system(size: 12).monospacedDigit())
                    .foregroundStyle(KLTokens.textSec)
                    .padding(.top, 8)
            }
        }
        .padding(.horizontal, 16)
    }

    // MARK: - 월별 라인 차트

    private var monthlyChart: some View {
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
