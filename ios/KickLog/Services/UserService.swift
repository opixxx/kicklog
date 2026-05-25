import Foundation
import SwiftData

// /users/me GET — 본인 프로필 조회.
@MainActor
final class UserService {
    static let shared = UserService()

    private let apiClient: any APIClient = URLSessionAPIClient()

    func fetchMe(into context: ModelContext) async throws -> User {
        let dto: UserDTO = try await apiClient.get("/users/me", query: nil)
        return User.upsert(from: dto, into: context)
    }
}
