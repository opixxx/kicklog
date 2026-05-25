import SwiftUI
import SwiftData

// 라벨링 시 운동장 선택 sheet.
// 서버 Venue 목록을 SwiftData 에 캐시하고, 새 운동장은 /venues 생성 후 선택한다.
struct VenueSelectionScreen: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \Venue.name)
    private var venues: [Venue]

    let onSelect: (Venue) -> Void

    @State private var searchText: String = ""
    @State private var showingAddAlert: Bool = false
    @State private var newVenueName: String = ""
    @State private var isLoadingRemote: Bool = false
    @State private var isCreatingVenue: Bool = false
    @State private var errorMessage: String?

    private var filteredVenues: [Venue] {
        guard !searchText.trimmingCharacters(in: .whitespaces).isEmpty else { return venues }
        return venues.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                searchBar
                statusArea
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
                    Task { await addNewVenue() }
                }
                .disabled(newVenueName.trimmingCharacters(in: .whitespaces).isEmpty)
            } message: {
                Text("이름만 입력하시면 됩니다. 위치는 후속 단계에서 자동 보정됩니다.")
            }
            .task {
                await loadRemoteVenuesIfAuthenticated()
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
            if isLoadingRemote {
                ProgressView()
                    .scaleEffect(0.8)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(KLTokens.chipBg, in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    @ViewBuilder
    private var statusArea: some View {
        if let errorMessage {
            Text(errorMessage)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(KLTokens.loseFg)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(KLTokens.loseBg, in: RoundedRectangle(cornerRadius: 9))
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 6)
        }
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
                    Text(addVenueLabel)
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
        .disabled(isCreatingVenue)
    }

    private var addVenueLabel: String {
        if isCreatingVenue { return "추가 중..." }
        return searchText.isEmpty ? "새 운동장 추가" : "“\(searchText)” 추가"
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
            .disabled(isCreatingVenue)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
    }

    // MARK: - 새 추가

    private func addNewVenue() async {
        let name = newVenueName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }

        errorMessage = nil

        if AuthTokenStore.shared.isAuthenticated {
            isCreatingVenue = true
            defer { isCreatingVenue = false }
            do {
                let venue = try await VenueService.shared.createVenue(name: name, into: modelContext)
                onSelect(venue)
                newVenueName = ""
                searchText = ""
                dismiss()
                return
            } catch {
                let message = friendlyMessage(error)
                await loadRemoteVenuesIfAuthenticated()
                errorMessage = message
                return
            }
        }

        // 로그아웃 상태에서는 기존 동작처럼 로컬 임시 venue 를 만든다.
        // 이 Venue 로 저장한 Match 는 로그인 후 서버 Venue 로 교체하기 전까지 sync 보류된다.
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

    private func loadRemoteVenuesIfAuthenticated() async {
        guard AuthTokenStore.shared.isAuthenticated else { return }
        isLoadingRemote = true
        defer { isLoadingRemote = false }

        do {
            _ = try await VenueService.shared.fetchVenues(into: modelContext)
            errorMessage = nil
        } catch {
            errorMessage = friendlyMessage(error)
        }
    }

    private func friendlyMessage(_ error: Error) -> String {
        if let apiError = error as? APIError {
            switch apiError {
            case .noConnection:
                return "네트워크 연결을 확인해 주세요"
            case .unauthorized:
                return "로그인이 만료되었습니다"
            case .server(_, let body, _):
                return body?.message ?? "운동장 저장 중 서버 오류가 발생했습니다"
            case .decodingFailed:
                return "운동장 응답을 처리하지 못했습니다"
            case .unknown:
                return "운동장 저장 중 알 수 없는 오류가 발생했습니다"
            }
        }
        return error.localizedDescription
    }
}
