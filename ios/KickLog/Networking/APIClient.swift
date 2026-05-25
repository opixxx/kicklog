import Foundation

protocol APIClient {
    func get<T: Decodable>(_ path: String, query: [URLQueryItem]?) async throws -> T
    func post<T: Decodable, B: Encodable>(_ path: String, body: B) async throws -> T
    func put<T: Decodable, B: Encodable>(_ path: String, body: B) async throws -> T
    func patch<T: Decodable, B: Encodable>(_ path: String, body: B) async throws -> T
    func delete<T: Decodable>(_ path: String) async throws -> T
}

// URLSession 기반 클라이언트. ISO8601 Date + Bearer Authorization 자동 주입.
// Refresh token rotation 은 E2 단계에서 정교화 — 1차는 401 발생 시 그대로 throw.
final class URLSessionAPIClient: APIClient {
    let config: APIConfig
    let tokenStore: AuthTokenStore
    let session: URLSession
    let decoder: JSONDecoder
    let encoder: JSONEncoder

    init(
        config: APIConfig = .current,
        tokenStore: AuthTokenStore = .shared,
        session: URLSession = .shared
    ) {
        self.config = config
        self.tokenStore = tokenStore
        self.session = session

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder
    }

    func get<T: Decodable>(_ path: String, query: [URLQueryItem]? = nil) async throws -> T {
        try await request(method: "GET", path: path, query: query, body: nil as Empty?)
    }

    func post<T: Decodable, B: Encodable>(_ path: String, body: B) async throws -> T {
        try await request(method: "POST", path: path, query: nil, body: body)
    }

    func put<T: Decodable, B: Encodable>(_ path: String, body: B) async throws -> T {
        try await request(method: "PUT", path: path, query: nil, body: body)
    }

    func patch<T: Decodable, B: Encodable>(_ path: String, body: B) async throws -> T {
        try await request(method: "PATCH", path: path, query: nil, body: body)
    }

    func delete<T: Decodable>(_ path: String) async throws -> T {
        try await request(method: "DELETE", path: path, query: nil, body: nil as Empty?)
    }

    // MARK: - 공통 요청

    private func request<T: Decodable, B: Encodable>(
        method: String,
        path: String,
        query: [URLQueryItem]?,
        body: B?
    ) async throws -> T {
        var components = URLComponents(url: config.baseURL.appendingPathComponent(path),
                                       resolvingAgainstBaseURL: false)
        if let query, !query.isEmpty {
            components?.queryItems = query
        }
        guard let url = components?.url else {
            throw APIError.unknown(underlying: NSError(domain: "APIClient", code: -1,
                                                       userInfo: [NSLocalizedDescriptionKey: "잘못된 URL"]))
        }

        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token = tokenStore.accessToken {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        if let body {
            req.httpBody = try encoder.encode(body)
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: req)
        } catch let urlError as URLError where urlError.code == .notConnectedToInternet {
            throw APIError.noConnection
        } catch {
            throw APIError.unknown(underlying: error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw APIError.unknown(underlying: NSError(domain: "APIClient", code: -2,
                                                       userInfo: [NSLocalizedDescriptionKey: "HTTP 응답 아님"]))
        }

        switch http.statusCode {
        case 200..<300:
            // 204 No Content / 빈 응답
            if data.isEmpty, let empty = EmptyResponse() as? T {
                return empty
            }
            do {
                return try decoder.decode(T.self, from: data)
            } catch {
                throw APIError.decodingFailed(underlying: error)
            }
        case 401:
            let body = try? decoder.decode(APIErrorBody.self, from: data)
            throw APIError.unauthorized(body: body)
        default:
            let body = try? decoder.decode(APIErrorBody.self, from: data)
            let raw = String(data: data, encoding: .utf8) ?? ""
            throw APIError.server(status: http.statusCode, body: body, raw: raw)
        }
    }
}

// MARK: - 빈 body / 빈 응답 — Encodable/Decodable 형식 통일용

private struct Empty: Encodable {}

struct EmptyResponse: Decodable {}
