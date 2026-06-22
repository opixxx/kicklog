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

    // MARK: - 앱 시작 복구

    // 백엔드의 라벨링 경기를 전체 페이지 순회하며 로컬로 선복구한다.
    // 기기 재설치로 로컬 store 가 비워진 뒤, HealthKit 재import 보다 먼저 호출해야
    // 같은 워크아웃이 미라벨 경기로 중복 생성되는 것을 막을 수 있다 (KickLogApp.task 1단계).
    func restoreLabeledMatches(in context: ModelContext) async {
        guard AuthTokenStore.shared.isAuthenticated else { return }

        // 1) 목록(summary)으로 전체 경기 serverId 수집.
        var cursor: String? = nil
        var serverIds: [Int64] = []
        repeat {
            guard let response = try? await fetchMatches(cursor: cursor, size: 50, into: context) else { break }
            serverIds.append(contentsOf: response.content.map { $0.id })
            cursor = response.hasNext ? response.nextCursor : nil
        } while cursor != nil

        // 2) 각 경기의 상세(쿼터 포함)까지 복구한다.
        //    목록 API(summary)는 쿼터를 주지 않으므로, 쿼터 없이 복구하면 HealthKit import 의
        //    중복 제거(sourceWorkoutUUID/시각 매칭)와 cleanup 이 비교 대상이 없어 미라벨 중복을 못 막는다.
        //    상세 복구로 라벨 경기에 쿼터(healthKitWorkoutId)가 채워져야 dedup 이 UUID 로 정확히 매칭된다.
        for serverId in serverIds {
            _ = try? await fetchMatch(serverId: serverId, into: context)
        }
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
            context.saveOrLog(caller: "MatchSyncService.sync(incomplete)")
            return
        }

        let path = "/matches/\(match.clientMatchId.uuidString)"
        do {
            let response: MatchDetailResponse = try await apiClient.put(path, body: request)
            Match.upsertDetail(from: response, into: context)
            context.saveOrLog(caller: "MatchSyncService.sync(success)")
        } catch {
            match.lastSyncAttemptAt = .now
            match.syncErrorMessage = error.localizedDescription
            context.saveOrLog(caller: "MatchSyncService.sync(failure)")
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
