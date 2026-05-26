import Foundation
import SwiftData

// ADR-0003 D9 fire-and-forget — Match 를 백엔드로 PUT.
// 성공: serverId/syncedAt 갱신. 실패: lastSyncAttemptAt/syncErrorMessage 기록 후 재시도 큐로.
@MainActor
final class MatchSyncService {
    static let shared = MatchSyncService()

    private let apiClient: any APIClient = URLSessionAPIClient()

    // MARK: - 조회

    func fetchMatches(cursor: String? = nil, size: Int = 20, into context: ModelContext) async throws -> MatchListResponse {
        guard AuthTokenStore.shared.isAuthenticated else {
            return MatchListResponse(content: [], size: size, nextCursor: nil, hasNext: false)
        }

        var query = [URLQueryItem(name: "size", value: String(size))]
        if let cursor {
            query.append(URLQueryItem(name: "cursor", value: cursor))
        }

        let response: MatchListResponse = try await apiClient.get("/matches", query: query)
        response.content.forEach { Match.upsertSummary(from: $0, into: context) }
        return response
    }

    @discardableResult
    func fetchMatch(serverId: Int64, into context: ModelContext) async throws -> Match {
        let response: MatchDetailResponse = try await apiClient.get("/matches/\(serverId)", query: nil)
        return Match.upsertDetail(from: response, into: context)
    }

    @discardableResult
    func fetchMatch(clientMatchId: UUID, into context: ModelContext) async throws -> Match {
        let response: MatchDetailResponse = try await apiClient.get(
            "/matches/by-client-id/\(clientMatchId.uuidString)",
            query: nil
        )
        return Match.upsertDetail(from: response, into: context)
    }

    // MARK: - 삭제

    func delete(_ match: Match, in context: ModelContext) async throws {
        if let serverId = match.serverId {
            guard AuthTokenStore.shared.isAuthenticated else {
                throw APIError.unauthorized(body: nil)
            }
            let _: EmptyResponse = try await apiClient.delete("/matches/\(serverId)")
        }
        context.delete(match)
        try context.save()
    }

    // MARK: - 단건 동기화

    func sync(_ match: Match, in context: ModelContext) async {
        // 인증 토큰 없으면 sync 안 함 (로그아웃 상태)
        guard AuthTokenStore.shared.isAuthenticated else { return }
        // 라벨링 안 된 매치는 sync 대상 아님
        guard match.labeledAt != nil else { return }
        guard let request = match.toPutRequest() else {
            // venueId 음수 또는 quarters 없음 — 사용자 입력 미완성. syncErrorMessage 만 기록.
            match.lastSyncAttemptAt = .now
            match.syncErrorMessage = "운동장/쿼터 정보 미완성 — sync 보류"
            try? context.save()
            return
        }

        let path = "/matches/\(match.clientMatchId.uuidString)"
        do {
            let response: MatchDetailResponse = try await apiClient.put(path, body: request)
            Match.upsertDetail(from: response, into: context)
            try? context.save()
        } catch {
            match.lastSyncAttemptAt = .now
            match.syncErrorMessage = error.localizedDescription
            try? context.save()
            print("MatchSyncService.sync 실패 \(match.clientMatchId): \(error)")
        }
    }

    // MARK: - 미동기화 일괄 처리

    // 앱 진입 시 / 네트워크 회복 시 호출. labeledAt != nil 이면서 syncedAt == nil 인 모든 Match 를 순차 PUT.
    func syncPending(in context: ModelContext) async {
        guard AuthTokenStore.shared.isAuthenticated else { return }

        let descriptor = FetchDescriptor<Match>(
            predicate: #Predicate { $0.labeledAt != nil && $0.syncedAt == nil },
            sortBy: [SortDescriptor(\.playedAt)]
        )
        guard let pending = try? context.fetch(descriptor), !pending.isEmpty else { return }

        for match in pending {
            await sync(match, in: context)
        }
    }
}
