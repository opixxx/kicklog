import Foundation
import SwiftData

// /users/me GET — 본인 프로필 조회.
@MainActor
final class UserService {
    static let shared = UserService()

    private let apiClient: any APIClient = URLSessionAPIClient()

    func fetchMe(into context: ModelContext) async throws -> User {
        let dto: UserDTO = try await apiClient.get("/users/me", query: nil)
        return upsert(dto: dto, into: context)
    }

    private func upsert(dto: UserDTO, into context: ModelContext) -> User {
        let serverId = dto.id
        let descriptor = FetchDescriptor<User>(
            predicate: #Predicate { $0.serverId == serverId }
        )
        if let existing = try? context.fetch(descriptor).first {
            existing.displayName = dto.displayName
            existing.email = dto.email
            existing.hideHeartRate = dto.hideHeartRate
            existing.lastSyncedAt = .now
            try? context.save()
            return existing
        }
        let user = User(
            serverId: dto.id,
            displayName: dto.displayName,
            email: dto.email,
            hideHeartRate: dto.hideHeartRate,
            createdAt: .now,
            lastSyncedAt: .now
        )
        context.insert(user)
        try? context.save()
        return user
    }
}
