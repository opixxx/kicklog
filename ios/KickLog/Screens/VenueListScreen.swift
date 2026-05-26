import SwiftUI
import SwiftData

// 내 운동장 목록 — Settings "내 운동장 관리" 진입점.
// 서버 GET /venues 결과를 SwiftData 에 캐시하고, 행 탭 시 VenueDetailScreen 으로 이동.
// 우상단 + 버튼은 VenueSelectionScreen 을 띄워 등록 흐름을 재사용한다.
struct VenueListScreen: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \Venue.name) private var venues: [Venue]
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showingAddSheet = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if let errorMessage {
                    errorBanner(errorMessage)
                }

                if isLoading && venues.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity, minHeight: 200)
                } else if venues.isEmpty {
                    emptyState
                } else {
                    list
                }

                Color.clear.frame(height: 24)
            }
        }
        .background(KLTokens.bg)
        .navigationTitle("내 운동장")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: { showingAddSheet = true }) {
                    KLIcon(name: "plus", size: 18, color: KLTokens.pitch)
                }
                .accessibilityLabel("운동장 추가")
            }
        }
        .sheet(isPresented: $showingAddSheet, onDismiss: { Task { await load() } }) {
            VenueSelectionScreen { _ in /* 등록 후 onSelect 콜백 — 목록은 onDismiss 에서 재로드 */ }
        }
        .navigationDestination(for: Int64.self) { venueId in
            VenueDetailScreen(venueId: venueId)
        }
        .task { await load() }
        .refreshable { await load() }
    }

    // MARK: - 리스트

    private var list: some View {
        VStack(spacing: 0) {
            ForEach(Array(venues.enumerated()), id: \.element.persistentModelID) { index, venue in
                NavigationLink(value: venue.serverId) {
                    venueRow(venue, isLast: index == venues.count - 1)
                }
                .buttonStyle(.plain)
                .disabled(venue.serverId <= 0)              // 로컬 임시 venue 는 상세 없음
            }
        }
        .background(KLTokens.bgElev)
        .clipShape(RoundedRectangle(cornerRadius: KLTokens.radiusCard))
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .klCardShadow(scheme)
    }

    private func venueRow(_ venue: Venue, isLast: Bool) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(KLTokens.pitchSoft).frame(width: 36, height: 36)
                KLIcon(name: "soccerball", size: 18, color: KLTokens.pitch)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(venue.name)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(KLTokens.text)
                Text(coordinatesLabel(venue))
                    .font(.system(size: 12).monospacedDigit())
                    .foregroundStyle(KLTokens.textSec)
            }
            Spacer(minLength: 0)
            if venue.serverId > 0 {
                KLIcon(name: "chevron.right", size: 13, color: KLTokens.textTer)
            } else {
                Text("로컬")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(KLTokens.textSec)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(KLTokens.chipBg, in: Capsule())
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) {
            if !isLast {
                Rectangle()
                    .fill(KLTokens.sep)
                    .frame(height: 0.5)
                    .padding(.leading, 64)
            }
        }
    }

    private func coordinatesLabel(_ venue: Venue) -> String {
        guard venue.geoLat != 0 || venue.geoLng != 0 else { return "위치 정보 없음" }
        return String(format: "%.4f, %.4f", venue.geoLat, venue.geoLng)
    }

    // MARK: - Empty / Error

    private var emptyState: some View {
        VStack(spacing: 14) {
            KLIcon(name: "soccerball", size: 56, color: KLTokens.textTer)
            Text("등록된 운동장이 없습니다")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(KLTokens.text)
            Text("우상단 + 버튼으로 운동장을 추가해 보세요")
                .font(.system(size: 13))
                .foregroundStyle(KLTokens.textSec)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 80)
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            KLIcon(name: "exclamationmark.triangle.fill", size: 14, color: KLTokens.loseFg)
            Text(message)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(KLTokens.loseFg)
            Spacer()
            Button("재시도") { Task { await load() } }
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(KLTokens.loseFg)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(KLTokens.loseBg, in: RoundedRectangle(cornerRadius: 9))
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    // MARK: - Load

    private func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            _ = try await VenueService.shared.fetchVenues(into: modelContext)
        } catch {
            errorMessage = friendlyMessage(error)
        }
    }

    private func friendlyMessage(_ error: Error) -> String {
        guard let apiError = error as? APIError else { return error.localizedDescription }
        switch apiError {
        case .noConnection: return "네트워크 연결을 확인해 주세요"
        case .unauthorized: return "로그인이 만료되었습니다"
        case .server(_, let body, _): return body?.message ?? "운동장 로딩 중 서버 오류"
        case .decodingFailed: return "응답을 처리하지 못했습니다"
        case .unknown: return "알 수 없는 오류가 발생했습니다"
        }
    }
}

#Preview {
    NavigationStack { VenueListScreen() }
        .modelContainer(for: KickLogSchema.allModels, inMemory: true)
}
