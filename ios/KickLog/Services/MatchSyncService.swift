import Foundation
import SwiftData

// ADR-0003 D9 fire-and-forget — Match 를 백엔드로 PUT.
// 성공: serverId/syncedAt 갱신. 실패: lastSyncAttemptAt/syncErrorMessage 기록 후 재시도 큐로.
@MainActor
final class MatchSyncService {
    static let shared = MatchSyncService()

    private let apiClient: any APIClient = URLSessionAPIClient()

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
            match.serverId = response.id
            match.syncedAt = .now
            match.lastSyncAttemptAt = .now
            match.syncErrorMessage = nil
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
