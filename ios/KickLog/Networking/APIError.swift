import Foundation

// 백엔드 GlobalExceptionHandler 응답 매핑.
// CLAUDE.md / api-conventions: `{ code, message, field?, traceId? }`
struct APIErrorBody: Decodable {
    let code: String
    let message: String
    let field: String?
    let traceId: String?
}

enum APIError: LocalizedError {
    case noConnection                        // 네트워크 두절
    case decodingFailed(underlying: Error)   // JSON 파싱 실패
    case server(status: Int, body: APIErrorBody?, raw: String)
    case unauthorized(body: APIErrorBody?)   // 401 — refresh 또는 logout 처리
    case unknown(underlying: Error)

    var errorDescription: String? {
        switch self {
        case .noConnection: return "네트워크 연결을 확인해주세요."
        case .decodingFailed(let underlying): return "응답 파싱 실패: \(underlying.localizedDescription)"
        case .server(let status, let body, _):
            return body?.message ?? "서버 오류 (HTTP \(status))"
        case .unauthorized(let body):
            return body?.message ?? "인증이 만료되었습니다."
        case .unknown(let underlying): return underlying.localizedDescription
        }
    }
}
