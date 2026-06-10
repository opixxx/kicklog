import Foundation
import SwiftData

// /venues API — 개인 운동장 목록·생성·상세·수정·삭제.
@MainActor
final class VenueService {
    static let shared = VenueService()

    private let apiClient: any APIClient = URLSessionAPIClient()

    // MARK: - 목록 (6.1)

    func fetchVenues(into context: ModelContext) async throws -> [Venue] {
        let response: VenueListResponse = try await apiClient.get("/venues", query: nil)
        return response.venues.map { Venue.upsert(from: $0, into: context) }
    }

    // MARK: - 생성 (6.2)

    func createVenue(
        name: String,
        geoLat: Double = 0,
        geoLng: Double = 0,
        address: String? = nil,
        roadAddress: String? = nil,
        provider: String? = nil,
        providerPlaceId: String? = nil,
        into context: ModelContext
    ) async throws -> Venue {
        let request = CreateVenueRequest(
            name: name,
            geoLat: geoLat,
            geoLng: geoLng,
            address: address,
            roadAddress: roadAddress,
            provider: provider,
            providerPlaceId: providerPlaceId
        )
        let response: VenueResponse = try await apiClient.post("/venues", body: request)
        return Venue.upsert(from: response, into: context)
    }

    // 카카오 PlaceItem 으로 바로 등록.
    func createVenue(from place: PlaceItem, into context: ModelContext) async throws -> Venue {
        try await createVenue(
            name: place.name,
            geoLat: place.lat,
            geoLng: place.lng,
            address: place.address,
            roadAddress: place.roadAddress,
            provider: place.provider,
            providerPlaceId: place.providerPlaceId,
            into: context
        )
    }

    // MARK: - 상세 (6.3)

    func fetchVenue(id: Int64, into context: ModelContext) async throws -> Venue {
        let response: VenueResponse = try await apiClient.get("/venues/\(id)", query: nil)
        return Venue.upsert(from: response, into: context)
    }

    // MARK: - 수정 (6.4) — 좌표 불변, 이름만 변경 가능

    func updateVenue(id: Int64, name: String, into context: ModelContext) async throws -> Venue {
        let response: VenueResponse = try await apiClient.patch(
            "/venues/\(id)",
            body: UpdateVenueRequest(name: name)
        )
        return Venue.upsert(from: response, into: context)
    }

    // MARK: - 삭제 (6.5) — 관련 matches.venue_id 는 백엔드에서 NULL 처리

    func deleteVenue(id: Int64, in context: ModelContext) async throws {
        let _: EmptyResponse = try await apiClient.delete("/venues/\(id)")
        let descriptor = FetchDescriptor<Venue>(
            predicate: #Predicate { $0.serverId == id }
        )
        if let local = try? context.fetch(descriptor).first {
            context.delete(local)
            context.saveOrLog(caller: "VenueService.deleteVenue")
        }
    }
}
