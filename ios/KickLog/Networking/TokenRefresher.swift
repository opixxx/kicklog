import Foundation

// 401 발생 시 access token 자동 재발급. api-spec.md §1.3 — refresh token rotation.
// 동시 다발 401 요청이 들어와도 단 한 번의 /auth/refresh 만 호출되도록 inflight Task 캐싱.
actor TokenRefresher {
    static let shared = TokenRefresher()

    private var refreshTask: Task<Bool, Never>?
    private let config: APIConfig
    private let tokenStore: AuthTokenStore

    init(config: APIConfig = .current, tokenStore: AuthTokenStore = .shared) {
        self.config = config
        self.tokenStore = tokenStore
    }

    // true: 새 access token 발급 성공. false: refresh token 없음/만료/거부 (호출자는 logout 흐름).
    func refresh() async -> Bool {
        if let existing = refreshTask {
            return await existing.value
        }
        let task = Task<Bool, Never> { await self.performRefresh() }
        refreshTask = task
        let result = await task.value
        refreshTask = nil
        return result
    }

    private func performRefresh() async -> Bool {
        guard let refreshToken = tokenStore.refreshToken else { return false }

        var req = URLRequest(url: config.baseURL.appendingPathComponent("/auth/refresh"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            req.httpBody = try encoder.encode(RefreshRequest(refreshToken: refreshToken))
        } catch {
            print("TokenRefresher: encode 실패 — \(error)")
            return false
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: req)
        } catch {
            // 네트워크 실패 — refresh token 살아있을 수 있음. clear 하지 않고 false 만 반환 (다음 시도 가능).
            print("TokenRefresher: 네트워크 실패 — \(error)")
            return false
        }

        guard let http = response as? HTTPURLResponse else { return false }
        guard (200..<300).contains(http.statusCode) else {
            // 401 (AUTH_INVALID_REFRESH/EXPIRED/REUSED) 또는 4xx — refresh 영구 실패. 토큰 정리.
            if (400..<500).contains(http.statusCode) {
                tokenStore.clear()
            }
            return false
        }

        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let decoded = try decoder.decode(RefreshResponse.self, from: data)
            // rotation 패턴 — 새 refreshToken 으로 교체
            tokenStore.save(accessToken: decoded.accessToken, refreshToken: decoded.refreshToken)
            return true
        } catch {
            print("TokenRefresher: decode 실패 — \(error)")
            return false
        }
    }
}
