import SwiftUI

// 라벨링 화면 — Apple Watch 자동 감지 워크아웃을 경기로 확정하는 modal sheet.
// JSX labeling.jsx 의 메인 변형 (KLTrimSheetScreen 변형은 dual-thumb 슬라이더 필요 — TODO).
struct LabelingScreen: View {
    let item: LabelingQueueItem
    @Environment(\.dismiss) private var dismiss

    // 폼 상태
    @State private var q1Selected: Bool = true
    @State private var q2Selected: Bool = true
    @State private var q2NeedsAdjust: Bool = true   // 32분 워닝 케이스
    @State private var q3Selected: Bool = false
    @State private var q4Selected: Bool = true

    @State private var result: MatchResult = .win
    @State private var position: String = "MF"
    @State private var goals: Int = 2
    @State private var assists: Int = 1

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    detectedWorkoutSection
                    quartersSection
                    warningCard
                    metadataSection
                    Color.clear.frame(height: 30)
                }
            }
            .background(KLTokens.bg)
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
                    Button("저장") { dismiss() }
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(KLTokens.pitch)
                }
            }
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
                    Text("\(item.detectedQuarters)개 워크아웃")
                        .font(.system(size: 12, weight: .medium).monospacedDigit())
                        .foregroundStyle(KLTokens.textSec)
                }
                Text("\(item.date) \(item.time)")
                    .font(.system(size: 16, weight: .bold).monospacedDigit())
                    .tracking(-0.3)
                    .foregroundStyle(KLTokens.text)
                Text("마포 풋살장")
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

    // MARK: - 쿼터 선택

    private var quartersSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("내가 뛴 쿼터 · 출전한 쿼터만 체크하세요")
            HStack(spacing: 8) {
                KLQuarterChip(quarter: "Q1", minutes: 25,
                              state: q1Selected ? .on : .off,
                              onTap: { q1Selected.toggle() })
                KLQuarterChip(quarter: "Q2", minutes: 32,
                              state: q2Selected && q2NeedsAdjust ? .warn : (q2Selected ? .on : .off),
                              onTap: { q2Selected.toggle() })
                KLQuarterChip(quarter: "Q3", minutes: 25,
                              state: q3Selected ? .on : .off,
                              onTap: { q3Selected.toggle() })
                KLQuarterChip(quarter: "Q4", minutes: 24,
                              state: q4Selected ? .on : .off,
                              onTap: { q4Selected.toggle() })
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)  // amber 외곽 공간 확보
        }
    }

    // MARK: - Q2 경고 카드

    @ViewBuilder
    private var warningCard: some View {
        if q2Selected && q2NeedsAdjust {
            HStack(alignment: .top, spacing: 12) {
                KLIcon(name: "exclamationmark.triangle.fill", size: 22, color: KLTokens.amber)
                    .padding(.top, 1)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Q2가 32분으로 감지되었습니다")
                        .font(.system(size: 14, weight: .bold))
                        .tracking(-0.2)
                        .foregroundStyle(KLTokens.text)
                    Text("워치 종료를 깜빡하셨다면 시간을 조정하세요. 30분 이상은 일반적이지 않아요.")
                        .font(.system(size: 13))
                        .foregroundStyle(KLTokens.textSec)
                        .lineSpacing(2)

                    Button(action: {}) {
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
    }

    @Environment(\.colorScheme) private var scheme
    private var amberButtonFg: Color {
        scheme == .dark ? KLTokens.amber : Color(hex: 0x9A5C00)
    }
    private var amberButtonBg: Color {
        scheme == .dark ? KLTokens.amber.opacity(0.18) : .white
    }

    // MARK: - 메타데이터 폼

    private var metadataSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("메타데이터 · 모두 선택")
            VStack(spacing: 0) {
                KLFormRow(label: "상대팀") {
                    Text("FC블루스")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(KLTokens.text)
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
                KLFormRow(label: "골") {
                    KLStepper(value: $goals)
                }
                KLFormRow(label: "어시스트") {
                    KLStepper(value: $assists)
                }
                KLFormRow(label: "운동장", isLast: true) {
                    HStack(spacing: 8) {
                        HStack(spacing: 4) {
                            Text("마포 풋살장")
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
                    }
                }
            }
            .background(KLTokens.bgElev)
            .clipShape(RoundedRectangle(cornerRadius: KLTokens.radiusCard))
            .padding(.horizontal, 16)
            .klCardShadow(scheme)
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
}

#Preview {
    LabelingScreen(item: LabelingQueueItem.samples[0])
}
