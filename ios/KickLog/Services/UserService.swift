import Foundation
import SwiftData

// /users/me — 본인 프로필 조회/수정/삭제.
@MainActor
final class UserService {
    static let shared = UserService()

    private let apiClient: any APIClient = URLSessionAPIClient()

    func fetchMe(into context: ModelContext) async throws -> User {
        let dto: UserDTO = try await apiClient.get("/users/me", query: nil)
        return User.upsert(from: dto, into: context)
    }

    func updateMe(
        displayName: String,
        into context: ModelContext
    ) async throws -> User {
        let request = UpdateMeRequest(displayName: displayName)
        let dto: UserDTO = try await apiClient.patch("/users/me", body: request)
        return User.upsert(from: dto, into: context)
    }

    // 닉네임 가용 확인 — 본인 현재 닉네임이거나 미사용이면 available=true (P1 V12 unique).
    func checkDisplayName(_ displayName: String) async throws -> DisplayNameCheckResponse {
        let items = [URLQueryItem(name: "displayName", value: displayName)]
        return try await apiClient.get("/users/check-display-name", query: items)
    }

    func deleteMe() async throws {
        let _: EmptyResponse = try await apiClient.delete("/users/me")
    }

    func cancelDeletion(into context: ModelContext) async throws -> User {
        let dto: UserDTO = try await apiClient.post("/users/me/cancel-deletion")
        return User.upsert(from: dto, into: context)
    }
}
