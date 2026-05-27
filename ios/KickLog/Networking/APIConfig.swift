import Foundation

// 백엔드 API 베이스 URL. DEBUG 빌드(시뮬레이터/실기기 Run)는 dev, Release/Archive(TestFlight) 는 prod.
struct APIConfig {
    let baseURL: URL

    static let dev = APIConfig(baseURL: URL(string: "http://localhost:8080")!)
    static let prod = APIConfig(baseURL: URL(string: "https://kicklog.org")!)

    static var current: APIConfig {
        #if DEBUG
        return .dev
        #else
        return .prod
        #endif
    }
}
