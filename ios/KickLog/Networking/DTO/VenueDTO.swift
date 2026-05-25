import Foundation

// api-spec.md §4 Venues — Request/Response DTO.

struct CreateVenueRequest: Encodable {
    let name: String
    let geoLat: Double
    let geoLng: Double
    let address: String?
    let roadAddress: String?
    let provider: String?
    let providerPlaceId: String?
}

struct VenueListResponse: Decodable {
    let venues: [VenueResponse]
}

struct VenueResponse: Decodable {
    let id: Int64
    let name: String
    let geoLat: Double
    let geoLng: Double
    let address: String?
    let roadAddress: String?
    let provider: String?
    let providerPlaceId: String?
    let createdAt: Date
}
