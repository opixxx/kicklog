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

    // 폼 상태 — 사용자가 출전한 쿼터 번호 (1~4). 시간순 워크아웃이 정렬된 체크 쿼터에 자동 매핑.
    @State private var selectedQuarterNumbers: Set<Int> = []
    @State private var opponent: String = ""
    @State private var position: String = "MF"
    @State private var userGoals: Int = 0
    @State private var teamGoals: Int = 0     // V10+ : 팀 전체 골 — result 는 백엔드가 자동 derive.
    @State private var opponentGoals: Int = 0
    @State private var userAssists: Int = 0
    @State private var selectedVenue: Venue?
    @State private var showingVenueSheet: Bool = false
    @State private var trimTargetQuarter: QuarterWorkout?

    private var amberButtonFg: Color {
        scheme == .dark ? KLTokens.amber : Color(hex: 0x9A5C00)
    }
    private var amberButtonBg: Color {
        scheme == .dark ? KLTokens.amber.opacity(0.18) : .white
    }

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
        .sheet(isPresented: $showingVenueSheet) {
            VenueSelectionScreen { venue in
                selectedVenue = venue
            }
        }
        .sheet(item: $trimTargetQuarter) { quarter in
            // 매핑된 quarterNo 찾기 — 시간순 워크아웃 index 위치의 selectedQuarterNumbers 정렬값
            let workoutIndex = detectedQuarters.firstIndex { $0.persistentModelID == quarter.persistentModelID } ?? 0
            let sortedSelected = selectedQuarterNumbers.sorted()
            let label = (workoutIndex < sortedSelected.count) ? "Q\(sortedSelected[workoutIndex])" : "Q?"
            TrimSheet(
                label: label,
                detectedStart: quarter.startedAt,
                detectedEnd: quarter.endedAt
            ) { newStart, newEnd in
                Task {
                    await quarter.retrim(
                        newStart: newStart,
                        newEnd: newEnd,
                        store: HealthKitService.shared.store,
                        analyzer: WorkoutAnalyzer()
                    )
                    try? modelContext.save()
                }
            }
        }
    }

    // MARK: - 초기 상태

    private func loadInitialState() {
        // 디폴트: 시간순 워크아웃 수만큼 앞 쿼터부터 선택 (예: 3개 → Q1·Q2·Q3).
        // 기존 quarterNo (재라벨링 시) 가 있으면 그것 우선 복원.
        let existingNumbers = detectedQuarters.compactMap { $0.quarterNo > 0 ? $0.quarterNo : nil }
        if !existingNumbers.isEmpty {
            selectedQuarterNumbers = Set(existingNumbers)
        } else {
            let count = min(detectedQuarters.count, 4)
            selectedQuarterNumbers = count > 0 ? Set(1...count) : []
        }
        opponent = match.opponentName ?? ""
        position = match.position ?? "MF"
        userGoals = match.userGoals ?? 0
        // teamGoals 가 미입력(nil) 이면 본인 골 수와 동일하게 초기화 — cross-field 검증 통과 + 자연스러운 default.
        teamGoals = match.teamGoals ?? (match.userGoals ?? 0)
        opponentGoals = match.opponentGoals ?? 0
        userAssists = match.userAssists ?? 0
        // venueId 로 기존 Venue 조회
        if let venueId = match.venueId {
            let descriptor = FetchDescriptor<Venue>(
                predicate: #Predicate { $0.serverId == venueId }
            )
            selectedVenue = try? modelContext.fetch(descriptor).first
        }
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
            sectionHeader("내가 뛴 쿼터 · 출전한 쿼터만 체크하세요 (체크 수 = 워크아웃 수)")
            HStack(spacing: 8) {
                ForEach(1...4, id: \.self) { quarterNo in
                    let mapped = mappedWorkout(forQuarter: quarterNo)
                    let minutes = mapped.map { Int($0.durationSeconds / 60) } ?? 0
                    let isSelected = selectedQuarterNumbers.contains(quarterNo)
                    let isOvertime = (mapped?.durationSeconds ?? 0) > 30 * 60
                    let state: KLQuarterChip.State =
                        isSelected
                        ? (isOvertime ? .warn : .on)
                        : .off
                    KLQuarterChip(quarter: "Q\(quarterNo)", minutes: minutes, state: state) {
                        toggleQuarter(quarterNo)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
    }

    // 선택된 쿼터들 (정렬) 의 i 번째 = 시간순 워크아웃의 i 번째. 그 매핑된 워크아웃 반환.
    private func mappedWorkout(forQuarter quarterNo: Int) -> QuarterWorkout? {
        guard selectedQuarterNumbers.contains(quarterNo) else { return nil }
        let sortedSelected = selectedQuarterNumbers.sorted()
        guard let mapIndex = sortedSelected.firstIndex(of: quarterNo) else { return nil }
        guard mapIndex < detectedQuarters.count else { return nil }
        return detectedQuarters[mapIndex]
    }

    private func toggleQuarter(_ quarterNo: Int) {
        if selectedQuarterNumbers.contains(quarterNo) {
            selectedQuarterNumbers.remove(quarterNo)
        } else {
            // 워크아웃 수 초과해서 선택 불가 (매핑 못 함)
            guard selectedQuarterNumbers.count < detectedQuarters.count else { return }
            selectedQuarterNumbers.insert(quarterNo)
        }
    }

    // MARK: - 30분 초과 경고

    // 매핑된 워크아웃 중 30분 초과 첫 번째 — (매핑된 quarterNo, 워크아웃) 튜플.
    private var overtimeMapping: (quarterNo: Int, workout: QuarterWorkout)? {
        let sortedSelected = selectedQuarterNumbers.sorted()
        for (mapIndex, qNo) in sortedSelected.enumerated() {
            guard mapIndex < detectedQuarters.count else { break }
            let w = detectedQuarters[mapIndex]
            if w.durationSeconds > 30 * 60 {
                return (qNo, w)
            }
        }
        return nil
    }

    private var shouldShowOvertimeWarning: Bool {
        overtimeMapping != nil
    }

    private var warningCard: some View {
        let overtime = overtimeMapping
        let label = overtime.map { "Q\($0.quarterNo)" } ?? "Q?"
        let minutes = overtime.map { Int($0.workout.durationSeconds / 60) } ?? 0
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

                Button {
                    trimTargetQuarter = overtime?.workout
                } label: {
                    HStack(spacing: 4) {
                        Text("시간 조정")
                            .font(.system(size: 13, weight: .bold))
                        KLIcon(name: "chevron.right", size: 12, color: amberButtonFg)
                    }
                    .foregroundStyle(amberButtonFg)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(amberButtonBg, in: Capsule())
                    .overlay(
                        Capsule().stroke(KLTokens.amber.opacity(0.4), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
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
                KLFormRow(label: "포지션") {
                    KLPositionChips(selection: $position)
                }
                KLFormRow(label: "본인 골") {
                    KLStepper(value: Binding(
                        get: { userGoals },
                        set: { newValue in
                            userGoals = newValue
                            // 본인 골이 팀 전체 골을 초과하면 팀 골 자동 보정 — 백엔드 cross-field 검증 사전 충족.
                            if teamGoals < userGoals { teamGoals = userGoals }
                        }
                    ))
                }
                KLFormRow(label: "팀 전체 골") {
                    KLStepper(value: Binding(
                        get: { teamGoals },
                        set: { newValue in
                            // 팀 골은 본인 골 이상이어야 한다 — 사용자가 본인 골보다 낮추려 하면 본인 골에서 멈춤.
                            teamGoals = max(newValue, userGoals)
                        }
                    ))
                }
                KLFormRow(label: "상대 골") {
                    KLStepper(value: $opponentGoals)
                }
                KLFormRow(label: "어시스트") {
                    KLStepper(value: $userAssists)
                }
                KLFormRow(label: "운동장", isLast: true) {
                    Button { showingVenueSheet = true } label: {
                        HStack(spacing: 8) {
                            if let venue = selectedVenue {
                                HStack(spacing: 4) {
                                    Text(venue.name)
                                        .font(.system(size: 13, weight: .bold))
                                    KLIcon(name: "checkmark", size: 11, color: KLTokens.pitch)
                                }
                                .foregroundStyle(KLTokens.pitch)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(KLTokens.pitchSoft, in: Capsule())
                                Text("변경")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(KLTokens.pitch)
                            } else {
                                Text("선택")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(KLTokens.pitch)
                                KLIcon(name: "chevron.right", size: 12, color: KLTokens.pitch)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .background(KLTokens.bgElev)
            .clipShape(RoundedRectangle(cornerRadius: KLTokens.radiusCard))
            .padding(.horizontal, 16)
            .klCardShadow(scheme)

            // 결과 자동 표시 — 팀골/상대골 조합으로 derive.
            HStack(spacing: 6) {
                KLIcon(name: "checkmark.seal.fill", size: 12, color: KLTokens.pitch)
                Text("결과: \(derivedResultLabel)")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(KLTokens.textSec)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
        }
    }

    private var derivedResult: MatchResult {
        if teamGoals > opponentGoals { return .win }
        if teamGoals < opponentGoals { return .lose }
        return .draw
    }

    private var derivedResultLabel: String {
        // 매치 카드 표시용 — 0:0 도 무승부로 노출 (백엔드 derive 와 일치).
        "\(teamGoals)-\(opponentGoals) \(derivedResult.rawValue)"
    }

    // MARK: - 저장 가능 조건

    private var canSave: Bool {
        // 체크된 쿼터 수 == 감지된 워크아웃 수 (1:1 매핑 강제) + 상대팀 이름 입력
        selectedQuarterNumbers.count == detectedQuarters.count
            && !opponent.trimmingCharacters(in: .whitespaces).isEmpty
    }

    // MARK: - 저장 흐름

    private func save() {
        // 1. 시간순 워크아웃을 정렬된 selectedQuarterNumbers 와 1:1 매핑.
        //    예: 워크아웃 3개 + 사용자가 Q1·Q2·Q4 체크 → 시간순 1→Q1, 2→Q2, 3→Q4.
        let sortedSelected = selectedQuarterNumbers.sorted()
        var matched: Set<PersistentIdentifier> = []
        for (mapIndex, quarterNo) in sortedSelected.enumerated() {
            guard mapIndex < detectedQuarters.count else { break }
            let workout = detectedQuarters[mapIndex]
            workout.quarterNo = quarterNo
            workout.match = match
            matched.insert(workout.persistentModelID)
        }

        // 매핑 안 된 워크아웃 (체크 수 < 워크아웃 수 인 경우 잉여) 은 분리.
        for workout in detectedQuarters where !matched.contains(workout.persistentModelID) {
            workout.quarterNo = 0
            workout.match = nil
        }

        // 2. Match 메타 업데이트.
        //    result 는 로컬에서도 teamGoals vs opponentGoals 로 derive — 백엔드와 동일 규칙.
        //    백엔드 PUT 응답이 권위지만, 동기화 전까지 카드 표시를 위해 미리 계산해둔다.
        match.opponentName = opponent.trimmingCharacters(in: .whitespaces)
        match.result = derivedResult.code
        match.position = position
        match.userGoals = userGoals
        match.teamGoals = teamGoals
        match.opponentGoals = opponentGoals
        match.userAssists = userAssists
        match.venueId = selectedVenue?.serverId
        match.venueName = selectedVenue?.name
        match.labeledAt = .now

        // 3. 헤드라인 4지표 재계산 (선택된 쿼터 기준)
        match.recalculateHeadlineMetrics()

        // 4. SwiftData 저장
        do {
            try modelContext.save()
        } catch {
            print("LabelingScreen: 저장 실패 — \(error)")
            return
        }

        // 5. 백엔드 PUT sync (ADR-0003 D9 fire-and-forget). 실패해도 dismiss.
        let matchToSync = match
        let contextToSync = modelContext
        Task {
            await MatchSyncService.shared.sync(matchToSync, in: contextToSync)
        }
        dismiss()
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
