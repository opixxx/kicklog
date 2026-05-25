import Foundation

// 백엔드 API 베이스 URL. 1차는 로컬 개발 서버 (시뮬레이터에서 http://localhost:8080 접근 가능).
// 추후 ADR-0006 의 production EC2 URL 로 환경별 분기.
struct APIConfig {
    let baseURL: URL

    static let dev = APIConfig(baseURL: URL(string: "http://localhost:8080")!)
    // static let prod = APIConfig(baseURL: URL(string: "https://api.kicklog.example.com")!)

    static var current: APIConfig { .dev }
}
