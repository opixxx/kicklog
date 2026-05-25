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
        displayName: String? = nil,
        hideHeartRate: Bool? = nil,
        into context: ModelContext
    ) async throws -> User {
        let request = UpdateMeRequest(displayName: displayName, hideHeartRate: hideHeartRate)
        let dto: UserDTO = try await apiClient.patch("/users/me", body: request)
        return User.upsert(from: dto, into: context)
    }

    func deleteMe() async throws {
        let _: EmptyResponse = try await apiClient.delete("/users/me")
    }

    func cancelDeletion(into context: ModelContext) async throws -> User {
        let dto: UserDTO = try await apiClient.post("/users/me/cancel-deletion")
        return User.upsert(from: dto, into: context)
    }
}
