import Foundation

// api-spec.md §7 Places — 카카오 로컬 키워드 검색 프록시 응답.

struct PlaceSearchResponse: Decodable {
    let places: [PlaceItem]
}

struct PlaceItem: Decodable, Hashable, Identifiable {
    let provider: String                  // "kakao"
    let providerPlaceId: String
    let name: String
    let address: String
    let roadAddress: String?
    let lat: Double
    let lng: Double
    let distanceM: Int?                   // lat/lng 미제공 시 null

    // ForEach 키 — 카카오 장소 id 가 provider 안에서 unique.
    var id: String { "\(provider):\(providerPlaceId)" }
}
