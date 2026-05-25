import Foundation

// JWT 토큰 저장소. Keychain wrapper + in-memory cache.
// access token 은 매 요청마다 읽으므로 캐시. refresh token 은 rotation 시에만.
final class AuthTokenStore {
    static let shared = AuthTokenStore()

    private let accessTokenKey = "auth.accessToken"
    private let refreshTokenKey = "auth.refreshToken"

    private(set) var accessToken: String?
    private(set) var refreshToken: String?

    private init() {
        self.accessToken = KeychainService.get(forKey: accessTokenKey)
        self.refreshToken = KeychainService.get(forKey: refreshTokenKey)
    }

    var isAuthenticated: Bool { accessToken != nil }

    func save(accessToken: String, refreshToken: String) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        KeychainService.set(accessToken, forKey: accessTokenKey)
        KeychainService.set(refreshToken, forKey: refreshTokenKey)
    }

    func updateAccessToken(_ token: String) {
        self.accessToken = token
        KeychainService.set(token, forKey: accessTokenKey)
    }

    func clear() {
        self.accessToken = nil
        self.refreshToken = nil
        KeychainService.remove(forKey: accessTokenKey)
        KeychainService.remove(forKey: refreshTokenKey)
    }
}
