import Foundation

// api-spec.md §1 Auth — Request/Response DTO.

struct AppleSignInRequest: Encodable {
    let identityToken: String
    let name: String?
}

struct KakaoSignInRequest: Encodable {
    let accessToken: String      // Kakao iOS SDK 에서 받은 토큰
    let name: String?
}

struct RefreshRequest: Encodable {
    let refreshToken: String
}

struct SignInResponse: Decodable {
    let accessToken: String
    let refreshToken: String
    let user: UserDTO
}

struct RefreshResponse: Decodable {
    let accessToken: String
    let refreshToken: String
}

struct LogoutRequest: Encodable {
    let refreshToken: String
}

// MARK: - User (api-spec.md §2 — share 됨)

struct UserDTO: Decodable {
    let id: Int64
    let displayName: String
    let email: String?
    let hideHeartRate: Bool
}
