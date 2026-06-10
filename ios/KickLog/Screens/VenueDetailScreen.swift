import SwiftUI
import SwiftData

// 운동장 상세 — GET /venues/{id} (6.3) + PATCH (6.4) + DELETE (6.5).
// SwiftData 로컬 캐시를 먼저 보여주고, .task 에서 서버 동기화. dismiss 후 부모에서 reload 한다.
struct VenueDetailScreen: View {
    let venueId: Int64
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme

    @Query private var venues: [Venue]
    @State private var isLoading = false
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @State private var showingRenameAlert = false
    @State private var renameInput: String = ""
    @State private var showingDeleteConfirm = false

    init(venueId: Int64) {
        self.venueId = venueId
        _venues = Query(filter: #Predicate<Venue> { $0.serverId == venueId })
    }

    private var venue: Venue? { venues.first }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if let errorMessage {
                    errorBanner(errorMessage)
                }
                if let venue {
                    header(venue)
                    metaCard(venue)
                    actionButtons
                } else if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, minHeight: 200)
                } else {
                    Text("운동장 정보를 찾을 수 없습니다")
                        .font(.system(size: 14))
                        .foregroundStyle(KLTokens.textSec)
                        .frame(maxWidth: .infinity, minHeight: 200)
                }
                Color.clear.frame(height: 24)
            }
        }
        .background(KLTokens.bg)
        .navigationTitle(venue?.name ?? "운동장")
        .navigationBarTitleDisplayMode(.inline)
        .alert("이름 수정", isPresented: $showingRenameAlert) {
            TextField("운동장 이름", text: $renameInput)
                .autocorrectionDisabled()
            Button("취소", role: .cancel) {}
            Button("저장") { Task { await rename() } }
                .disabled(renameInput.trimmingCharacters(in: .whitespaces).isEmpty)
        } message: {
            Text("좌표는 변경되지 않습니다 (위치가 다르면 새 운동장으로 등록).")
        }
        .alert("운동장 삭제", isPresented: $showingDeleteConfirm) {
            Button("취소", role: .cancel) {}
            Button("삭제", role: .destructive) { Task { await deleteVenue() } }
        } message: {
            Text("이 운동장을 사용한 과거 경기는 운동장 정보가 비어 표시됩니다.")
        }
        .task { await loadFromServer() }
    }

    // MARK: - 헤더

    private func header(_ venue: Venue) -> some View {
        VStack(spacing: 10) {
            ZStack {
                Circle().fill(KLTokens.pitchSoft).frame(width: 72, height: 72)
                KLIcon(name: "soccerball", size: 34, color: KLTokens.pitch)
            }
            Text(venue.name)
                .font(.system(size: 22, weight: .bold))
                .tracking(-0.4)
                .foregroundStyle(KLTokens.text)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 16)
        .padding(.bottom, 18)
    }

    // MARK: - 메타 카드

    private func metaCard(_ venue: Venue) -> some View {
        VStack(spacing: 0) {
            KLMetaRow(key: "이름", value: venue.name)
            KLMetaRow(key: "위도", value: coordValue(venue.geoLat))
            KLMetaRow(key: "경도", value: coordValue(venue.geoLng))
            KLMetaRow(key: "등록일", value: createdAtLabel(venue.createdAt), isLast: true)
        }
        .background(KLTokens.bgElev)
        .clipShape(RoundedRectangle(cornerRadius: KLTokens.radiusCard))
        .padding(.horizontal, 16)
        .klCardShadow(scheme)
    }

    private var actionButtons: some View {
        VStack(spacing: 10) {
            Button(action: {
                renameInput = venue?.name ?? ""
                showingRenameAlert = true
            }) {
                actionRow(icon: "pencil", text: "이름 수정", fg: KLTokens.text, bg: KLTokens.bgElev)
            }
            .buttonStyle(.plain)
            .disabled(venue == nil || isSubmitting)

            Button(role: .destructive, action: { showingDeleteConfirm = true }) {
                actionRow(icon: "trash", text: isSubmitting ? "삭제 중..." : "운동장 삭제",
                          fg: KLTokens.loseFg, bg: KLTokens.loseBg)
            }
            .buttonStyle(.plain)
            .disabled(venue == nil || isSubmitting)
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
    }

    private func actionRow(icon: String, text: String, fg: Color, bg: Color) -> some View {
        HStack(spacing: 8) {
            KLIcon(name: icon, size: 16, color: fg)
            Text(text)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(fg)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(bg, in: RoundedRectangle(cornerRadius: KLTokens.radiusCard))
    }

    private func errorBanner(_ message: String) -> some View {
        Text(message)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(KLTokens.loseFg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(KLTokens.loseBg, in: RoundedRectangle(cornerRadius: 9))
            .padding(.horizontal, 16)
            .padding(.top, 8)
    }

    // MARK: - Formatters

    private func coordValue(_ value: Double) -> String {
        value == 0 ? "—" : String(format: "%.6f", value)
    }

    private func createdAtLabel(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ko_KR")
        f.dateFormat = "yyyy년 M월 d일"
        return f.string(from: date)
    }

    // MARK: - API

    private func loadFromServer() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            _ = try await VenueService.shared.fetchVenue(id: venueId, into: modelContext)
        } catch {
            errorMessage = error.userMessage(serverCodes: [
                "VENUE_NOT_FOUND": "운동장을 찾을 수 없습니다",
                "VENUE_NOT_OWNED": "권한이 없는 운동장입니다",
                "VENUE_NAME_DUPLICATE": "같은 이름의 운동장이 이미 있습니다",
            ])
        }
    }

    private func rename() async {
        let name = renameInput.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        guard !isSubmitting else { return }
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }
        do {
            _ = try await VenueService.shared.updateVenue(id: venueId, name: name, into: modelContext)
        } catch {
            errorMessage = error.userMessage(serverCodes: [
                "VENUE_NOT_FOUND": "운동장을 찾을 수 없습니다",
                "VENUE_NOT_OWNED": "권한이 없는 운동장입니다",
                "VENUE_NAME_DUPLICATE": "같은 이름의 운동장이 이미 있습니다",
            ])
        }
    }

    private func deleteVenue() async {
        guard !isSubmitting else { return }
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }
        do {
            try await VenueService.shared.deleteVenue(id: venueId, in: modelContext)
            dismiss()
        } catch {
            errorMessage = error.userMessage(serverCodes: [
                "VENUE_NOT_FOUND": "운동장을 찾을 수 없습니다",
                "VENUE_NOT_OWNED": "권한이 없는 운동장입니다",
                "VENUE_NAME_DUPLICATE": "같은 이름의 운동장이 이미 있습니다",
            ])
        }
    }

}

#Preview {
    NavigationStack { VenueDetailScreen(venueId: 1) }
        .modelContainer(for: KickLogSchema.allModels, inMemory: true)
}
