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

// MARK: - 사용자 노출용 메시지 변환 (각 화면의 friendlyMessage 중복 통합)

extension Error {
    /// 사용자에게 보여줄 한글 오류 메시지. APIError 가 아니면 localizedDescription fallback.
    /// 화면별 서버 코드(예: FRIEND_UNAUTHORIZED) 분기는 `userMessage(serverCodes:serverFallback:)` 사용.
    var userMessage: String {
        userMessage(serverCodes: [:])
    }

    /// 서버 코드별 커스텀 메시지(`serverCodes`)와 `.server` 일반 fallback(`serverFallback`)을 지정 가능한 변형.
    /// - serverCodes: ErrorCode(예: "VENUE_NOT_FOUND") → 사용자 메시지 매핑. body.code 매칭 시 우선.
    /// - serverFallback: 매칭되는 코드가 없을 때 body.message 가 없으면 쓸 기본 문구.
    func userMessage(serverCodes: [String: String] = [:], serverFallback: String = "서버 오류가 발생했습니다") -> String {
        guard let apiError = self as? APIError else { return localizedDescription }
        switch apiError {
        case .noConnection: return "네트워크 연결을 확인해 주세요"
        case .unauthorized: return "로그인이 만료되었습니다"
        case .server(_, let body, _):
            if let code = body?.code, let mapped = serverCodes[code] { return mapped }
            return body?.message ?? serverFallback
        case .decodingFailed: return "응답을 처리하지 못했습니다"
        case .unknown: return "알 수 없는 오류가 발생했습니다"
        }
    }
}
