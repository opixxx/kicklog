import Foundation

// api-spec.md §7.1 GET /places/search — 카카오 로컬 키워드 검색 프록시.
// lat/lng 가 있으면 거리순 정렬 + distanceM 채워짐.
@MainActor
final class PlaceService {
    static let shared = PlaceService()

    private let apiClient: any APIClient = URLSessionAPIClient()

    func search(
        query: String,
        lat: Double? = nil,
        lng: Double? = nil,
        radius: Int? = nil
    ) async throws -> PlaceSearchResponse {
        var items: [URLQueryItem] = [URLQueryItem(name: "q", value: query)]
        if let lat { items.append(URLQueryItem(name: "lat", value: String(lat))) }
        if let lng { items.append(URLQueryItem(name: "lng", value: String(lng))) }
        if let radius { items.append(URLQueryItem(name: "radius", value: String(radius))) }
        return try await apiClient.get("/places/search", query: items)
    }
}
