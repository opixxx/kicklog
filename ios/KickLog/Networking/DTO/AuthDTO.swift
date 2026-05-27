import Foundation

// api-spec.md §1 Auth — Request/Response DTO.

struct AppleSignInRequest: Encodable {
    let identityToken: String
    let name: String?
}

struct KakaoSignInRequest: Encodable {
    let kakaoAccessToken: String      // Kakao iOS SDK 에서 받은 토큰
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
    let createdAt: Date
}

// PATCH /users/me — 백엔드에서 displayName 단일 필드 + @NotBlank 필수로 변경됨 (p0-cleanup).
struct UpdateMeRequest: Encodable {
    let displayName: String
}
