import SwiftUI
import SwiftData

// 라벨링 화면 — Apple Watch 자동 감지 Match (labeledAt == nil) 를 사용자가 확정하는 modal sheet.
// 저장 시 선택된 쿼터에 quarterNo 부여, labeledAt = .now, headline 재계산.
struct LabelingScreen: View {
    let match: Match
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var scheme

    // 감지된 모든 쿼터 (시간순). 라벨링 시점에는 match.quarters 가 4개 들어있음.
    private var detectedQuarters: [QuarterWorkout] {
        match.quarters.sorted { $0.startedAt < $1.startedAt }
    }

    // 폼 상태
    @State private var selectedQuarterIDs: Set<PersistentIdentifier> = []
    @State private var opponent: String = ""
    @State private var result: MatchResult = .draw
    @State private var position: String = "MF"
    @State private var userGoals: Int = 0
    @State private var opponentGoals: Int = 0
    @State private var userAssists: Int = 0

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    detectedWorkoutSection
                    quartersSection
                    if shouldShowOvertimeWarning {
                        warningCard
                    }
                    metadataSection
                    Color.clear.frame(height: 30)
                }
            }
            .background(KLTokens.bg)
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("취소") { dismiss() }
                        .foregroundStyle(KLTokens.textSec)
                }
                ToolbarItem(placement: .principal) {
                    Text("경기 라벨링")
                        .font(.system(size: 17, weight: .bold))
                        .tracking(-0.3)
                        .foregroundStyle(KLTokens.text)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("저장") { save() }
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(canSave ? KLTokens.pitch : KLTokens.textTer)
                        .disabled(!canSave)
                }
            }
        }
        .onAppear(perform: loadInitialState)
    }

    // MARK: - 초기 상태

    private func loadInitialState() {
        // 라벨링 화면 진입 시 모든 감지 쿼터 default 선택
        selectedQuarterIDs = Set(detectedQuarters.map(\.persistentModelID))
        opponent = match.opponentName ?? ""
        result = MatchResult.from(match.result)
        position = match.position ?? "MF"
        userGoals = match.userGoals ?? 0
        opponentGoals = match.opponentGoals ?? 0
        userAssists = match.userAssists ?? 0
    }

    // MARK: - 감지된 워크아웃

    private var detectedWorkoutSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("감지된 워크아웃")
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(KLTokens.pitch)
                        .frame(width: 28, height: 28)
                        .overlay(KLIcon(name: "watch", size: 16, color: .white))
                    Text("Apple Watch")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(KLTokens.text)
                    Spacer()
                    Text("\(detectedQuarters.count)개 워크아웃")
                        .font(.system(size: 12, weight: .medium).monospacedDigit())
                        .foregroundStyle(KLTokens.textSec)
                }
                Text(detectedDateRangeLabel)
                    .font(.system(size: 16, weight: .bold).monospacedDigit())
                    .tracking(-0.3)
                    .foregroundStyle(KLTokens.text)
                Text(venueDisplay)
                    .font(.system(size: 13))
                    .foregroundStyle(KLTokens.textSec)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: KLTokens.radiusCard)
                    .fill(KLTokens.pitchSoft)
                    .overlay(
                        RoundedRectangle(cornerRadius: KLTokens.radiusCard)
                            .stroke(KLTokens.pitch.opacity(0.18), lineWidth: 1)
                    )
            )
            .padding(.horizontal, 16)
        }
    }

    private var detectedDateRangeLabel: String {
        guard let first = detectedQuarters.first, let last = detectedQuarters.last else {
            return "—"
        }
        let date = Self.dateOnlyFormatter.string(from: first.startedAt)
        let start = Self.timeFormatter.string(from: first.startedAt)
        let end = Self.timeFormatter.string(from: last.endedAt)
        return "\(date) \(start) ~ \(end)"
    }

    private var venueDisplay: String {
        // venueId → Venue.name 은 C 묶음 도입 전까지 placeholder
        "운동장 미지정"
    }

    // MARK: - 쿼터 선택

    private var quartersSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("내가 뛴 쿼터 · 출전한 쿼터만 체크하세요")
            HStack(spacing: 8) {
                ForEach(Array(detectedQuarters.enumerated()), id: \.element.persistentModelID) { index, quarter in
                    let label = "Q\(index + 1)"
                    let minutes = Int(quarter.durationSeconds / 60)
                    let isSelected = selectedQuarterIDs.contains(quarter.persistentModelID)
                    let isOvertime = quarter.durationSeconds > 30 * 60
                    let state: KLQuarterChip.State =
                        isSelected
                        ? (isOvertime ? .warn : .on)
                        : .off
                    KLQuarterChip(quarter: label, minutes: minutes, state: state) {
                        toggleQuarter(quarter)
                    }
                }
                // 4개 미만이면 placeholder 칸으로 너비 균형
                ForEach(detectedQuarters.count..<4, id: \.self) { _ in
                    Color.clear.frame(maxWidth: .infinity, minHeight: 78)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
    }

    private func toggleQuarter(_ quarter: QuarterWorkout) {
        if selectedQuarterIDs.contains(quarter.persistentModelID) {
            selectedQuarterIDs.remove(quarter.persistentModelID)
        } else {
            selectedQuarterIDs.insert(quarter.persistentModelID)
        }
    }

    // MARK: - 30분 초과 경고

    private var overtimeQuarter: QuarterWorkout? {
        detectedQuarters
            .filter { selectedQuarterIDs.contains($0.persistentModelID) }
            .first { $0.durationSeconds > 30 * 60 }
    }

    private var shouldShowOvertimeWarning: Bool {
        overtimeQuarter != nil
    }

    private var warningCard: some View {
        let overtime = overtimeQuarter
        let label = overtime.map { quarter in
            let index = (detectedQuarters.firstIndex { $0.persistentModelID == quarter.persistentModelID } ?? 0) + 1
            return "Q\(index)"
        } ?? "Q?"
        let minutes = overtime.map { Int($0.durationSeconds / 60) } ?? 0
        return HStack(alignment: .top, spacing: 12) {
            KLIcon(name: "exclamationmark.triangle.fill", size: 22, color: KLTokens.amber)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 4) {
                Text("\(label)가 \(minutes)분으로 감지되었습니다")
                    .font(.system(size: 14, weight: .bold))
                    .tracking(-0.2)
                    .foregroundStyle(KLTokens.text)
                Text("워치 종료를 깜빡하셨다면 시간을 조정하세요. 30분 이상은 일반적이지 않아요.")
                    .font(.system(size: 13))
                    .foregroundStyle(KLTokens.textSec)
                    .lineSpacing(2)

                // 시간 조정 (Trim) 은 D 묶음에서 dual-thumb slider 도입
                Text("Trim 도구는 곧 추가됩니다")
                    .font(.system(size: 12))
                    .foregroundStyle(KLTokens.textTer)
                    .padding(.top, 6)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: KLTokens.radiusCard)
                .fill(KLTokens.amberSoft)
                .overlay(
                    RoundedRectangle(cornerRadius: KLTokens.radiusCard)
                        .stroke(KLTokens.amber.opacity(0.4), lineWidth: 1)
                )
        )
        .padding(.horizontal, 16)
        .padding(.top, 16)
    }

    // MARK: - 메타데이터 폼

    private var metadataSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("메타데이터 · 모두 선택")
            VStack(spacing: 0) {
                KLFormRow(label: "상대팀") {
                    TextField("팀 이름", text: $opponent)
                        .multilineTextAlignment(.trailing)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(KLTokens.text)
                        .submitLabel(.done)
                        .autocorrectionDisabled()
                        .frame(maxWidth: 180)
                }
                KLFormRow(label: "결과") {
                    KLSegmented(
                        options: [MatchResult.win, .draw, .lose],
                        selection: $result
                    )
                }
                KLFormRow(label: "포지션") {
                    KLPositionChips(selection: $position)
                }
                KLFormRow(label: "본인 골") {
                    KLStepper(value: $userGoals)
                }
                KLFormRow(label: "상대 골") {
                    KLStepper(value: $opponentGoals)
                }
                KLFormRow(label: "어시스트") {
                    KLStepper(value: $userAssists)
                }
                KLFormRow(label: "운동장", isLast: true) {
                    HStack(spacing: 8) {
                        Text("미지정")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(KLTokens.textSec)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(KLTokens.chipBg, in: Capsule())
                        Text("나중에")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(KLTokens.textTer)
                    }
                }
            }
            .background(KLTokens.bgElev)
            .clipShape(RoundedRectangle(cornerRadius: KLTokens.radiusCard))
            .padding(.horizontal, 16)
            .klCardShadow(scheme)

            // 결과 자동 추정 안내 — 사용자가 score 와 result 불일치하는 경우 시각 힌트
            if let suggested = suggestedResult, suggested != result {
                HStack(spacing: 6) {
                    KLIcon(name: "exclamationmark.triangle.fill", size: 12, color: KLTokens.amber)
                    Text("점수로는 \(suggested.rawValue) — 결과와 다릅니다")
                        .font(.system(size: 12))
                        .foregroundStyle(KLTokens.textSec)
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
            }
        }
    }

    private var suggestedResult: MatchResult? {
        guard userGoals != 0 || opponentGoals != 0 else { return nil }
        if userGoals > opponentGoals { return .win }
        if userGoals < opponentGoals { return .lose }
        return .draw
    }

    // MARK: - 저장 가능 조건

    private var canSave: Bool {
        // 최소 한 쿼터 선택 + 상대팀 이름 입력
        !selectedQuarterIDs.isEmpty && !opponent.trimmingCharacters(in: .whitespaces).isEmpty
    }

    // MARK: - 저장 흐름

    private func save() {
        // 1. 선택된 쿼터에 시간순 1,2,3,4 부여, 미선택은 0 + match relationship 해제
        let sortedAll = detectedQuarters
        let selectedSorted = sortedAll
            .filter { selectedQuarterIDs.contains($0.persistentModelID) }
            .sorted { $0.startedAt < $1.startedAt }

        for (index, quarter) in selectedSorted.enumerated() {
            quarter.quarterNo = index + 1
            quarter.match = match
        }

        for quarter in sortedAll where !selectedQuarterIDs.contains(quarter.persistentModelID) {
            quarter.quarterNo = 0
            quarter.match = nil
        }

        // 2. Match 메타 업데이트
        match.opponentName = opponent.trimmingCharacters(in: .whitespaces)
        match.result = result.code
        match.position = position
        match.userGoals = userGoals
        match.opponentGoals = opponentGoals
        match.userAssists = userAssists
        match.labeledAt = .now

        // 3. 헤드라인 4지표 재계산 (선택된 쿼터 기준)
        match.recalculateHeadlineMetrics()

        // 4. SwiftData 저장 — TODO: 후속 단계에서 백엔드 PUT sync (fire-and-forget)
        do {
            try modelContext.save()
            dismiss()
        } catch {
            print("LabelingScreen: 저장 실패 — \(error)")
        }
    }

    // MARK: - 섹션 헤더

    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13, weight: .medium))
            .tracking(-0.1)
            .foregroundStyle(KLTokens.textSec)
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 8)
    }

    // MARK: - Formatters

    private static let dateOnlyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ko_KR")
        f.dateFormat = "yyyy-MM-dd (E)"
        return f
    }()

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()
}

// MARK: - MatchResult → "W"/"D"/"L"

extension MatchResult {
    var code: String {
        switch self {
        case .win: return "W"
        case .draw: return "D"
        case .lose: return "L"
        }
    }
}
