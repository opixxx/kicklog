import Foundation
import SwiftData

// /venues API — 개인 운동장 목록/생성.
@MainActor
final class VenueService {
    static let shared = VenueService()

    private let apiClient: any APIClient = URLSessionAPIClient()

    func fetchVenues(into context: ModelContext) async throws -> [Venue] {
        let response: VenueListResponse = try await apiClient.get("/venues", query: nil)
        return response.venues.map { Venue.upsert(from: $0, into: context) }
    }

    func createVenue(
        name: String,
        geoLat: Double = 0,
        geoLng: Double = 0,
        into context: ModelContext
    ) async throws -> Venue {
        let request = CreateVenueRequest(
            name: name,
            geoLat: geoLat,
            geoLng: geoLng,
            address: nil,
            roadAddress: nil,
            provider: nil,
            providerPlaceId: nil
        )
        let response: VenueResponse = try await apiClient.post("/venues", body: request)
        return Venue.upsert(from: response, into: context)
    }
}
