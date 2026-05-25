import SwiftUI
import SwiftData

// 라벨링 시 운동장 선택 sheet.
// 기존 Venue 검색 + 새 운동장 추가 (이름만 — geo 는 0,0 placeholder, GPS 자동 채움은 후속).
struct VenueSelectionScreen: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \Venue.name)
    private var venues: [Venue]

    let onSelect: (Venue) -> Void

    @State private var searchText: String = ""
    @State private var showingAddAlert: Bool = false
    @State private var newVenueName: String = ""

    private var filteredVenues: [Venue] {
        guard !searchText.trimmingCharacters(in: .whitespaces).isEmpty else { return venues }
        return venues.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                searchBar
                listOrEmpty
            }
            .background(KLTokens.bg)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("취소") { dismiss() }
                        .foregroundStyle(KLTokens.textSec)
                }
                ToolbarItem(placement: .principal) {
                    Text("운동장 선택")
                        .font(.system(size: 17, weight: .bold))
                        .tracking(-0.3)
                        .foregroundStyle(KLTokens.text)
                }
            }
            .alert("새 운동장 추가", isPresented: $showingAddAlert) {
                TextField("운동장 이름", text: $newVenueName)
                    .autocorrectionDisabled()
                Button("취소", role: .cancel) {
                    newVenueName = ""
                }
                Button("추가") {
                    addNewVenue()
                }
                .disabled(newVenueName.trimmingCharacters(in: .whitespaces).isEmpty)
            } message: {
                Text("이름만 입력하시면 됩니다. 위치는 자동으로 보정됩니다.")
            }
        }
    }

    // MARK: - 검색 바

    private var searchBar: some View {
        HStack(spacing: 8) {
            KLIcon(name: "magnifyingglass", size: 16, color: KLTokens.textSec)
            TextField("운동장 검색", text: $searchText)
                .font(.system(size: 15))
                .autocorrectionDisabled()
                .submitLabel(.search)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(KLTokens.chipBg, in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    // MARK: - 리스트 + 빈 상태 + 새 추가

    @ViewBuilder
    private var listOrEmpty: some View {
        if filteredVenues.isEmpty {
            emptyView
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(filteredVenues.enumerated()), id: \.element.persistentModelID) { index, venue in
                        Button {
                            onSelect(venue)
                            dismiss()
                        } label: {
                            venueRow(venue, isLast: index == filteredVenues.count - 1)
                        }
                        .buttonStyle(.plain)
                    }
                    addNewButton
                }
                .background(KLTokens.bgElev)
                .clipShape(RoundedRectangle(cornerRadius: KLTokens.radiusCard))
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }
        }
    }

    private func venueRow(_ venue: Venue, isLast: Bool) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(KLTokens.pitchSoft).frame(width: 32, height: 32)
                KLIcon(name: "soccerball", size: 16, color: KLTokens.pitch)
            }
            Text(venue.name)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(KLTokens.text)
            Spacer(minLength: 0)
            KLIcon(name: "chevron.right", size: 13, color: KLTokens.textTer)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) {
            if !isLast {
                Rectangle()
                    .fill(KLTokens.sep)
                    .frame(height: 0.5)
                    .padding(.leading, 60)
            }
        }
    }

    private var addNewButton: some View {
        Button {
            newVenueName = searchText
            showingAddAlert = true
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(KLTokens.pitchSoft).frame(width: 32, height: 32)
                    KLIcon(name: "plus", size: 16, color: KLTokens.pitch)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(searchText.isEmpty ? "새 운동장 추가" : "“\(searchText)” 추가")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(KLTokens.pitch)
                    Text("이름만 입력하면 OK")
                        .font(.system(size: 12))
                        .foregroundStyle(KLTokens.textSec)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(KLTokens.sep)
                    .frame(height: 0.5)
                    .padding(.leading, 60)
            }
        }
        .buttonStyle(.plain)
    }

    private var emptyView: some View {
        VStack(spacing: 16) {
            KLIcon(name: "soccerball", size: 56, color: KLTokens.textTer)
            Text(searchText.isEmpty ? "등록된 운동장이 없습니다" : "“\(searchText)” 일치하는 운동장 없음")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(KLTokens.textSec)
                .multilineTextAlignment(.center)
            Button {
                newVenueName = searchText
                showingAddAlert = true
            } label: {
                HStack(spacing: 6) {
                    KLIcon(name: "plus", size: 14, color: .white)
                    Text(searchText.isEmpty ? "운동장 추가" : "“\(searchText)” 추가하기")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(KLTokens.pitch, in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
    }

    // MARK: - 새 추가

    private func addNewVenue() {
        let name = newVenueName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }

        // 로컬 추가 venue 는 음수 임시 serverId — 백엔드 sync 시 양수로 교체.
        // 기존 음수 serverId 중 가장 작은 값보다 하나 작게 부여.
        let descriptor = FetchDescriptor<Venue>(sortBy: [SortDescriptor(\.serverId)])
        let existingMinServerId = (try? modelContext.fetch(descriptor).first?.serverId) ?? 0
        let newServerId = min(existingMinServerId, 0) - 1

        let venue = Venue(serverId: newServerId, name: name, geoLat: 0, geoLng: 0)
        modelContext.insert(venue)
        do { try modelContext.save() } catch {
            print("VenueSelectionScreen: 저장 실패 — \(error)")
        }

        onSelect(venue)
        newVenueName = ""
        searchText = ""
        dismiss()
    }
}
