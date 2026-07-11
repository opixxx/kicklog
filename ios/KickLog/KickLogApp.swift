import SwiftUI
import SwiftData
import KakaoSDKAuth
import KakaoSDKCommon

@main
struct KickLogApp: App {
    @Environment(\.scenePhase) private var scenePhase

    // ADR-0004 D1 — CloudKit 미사용, 순수 로컬 SwiftData.
    let modelContainer: ModelContainer = {
        do {
            // VersionedSchema(V1) + MigrationPlan 경유 — 스키마 진화 대비.
            // V1 의 @Model 정의는 기존과 동일해 스키마 해시가 같으므로 기존 스토어가 그대로 열린다.
            let schema = Schema(versionedSchema: KickLogSchemaV1.self)
            let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
            return try ModelContainer(
                for: schema,
                migrationPlan: KickLogMigrationPlan.self,
                configurations: config
            )
        } catch {
            fatalError("ModelContainer 초기화 실패: \(error)")
        }
    }()

    init() {
        KakaoSDK.initSDK(appKey: Self.kakaoNativeAppKey)
    }

    private static var kakaoNativeAppKey: String {
        Bundle.main.object(forInfoDictionaryKey: "KAKAO_NATIVE_APP_KEY") as? String ?? ""
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .task {
                    // 1) 백엔드의 라벨링 경기를 먼저 로컬로 복구한다.
                    //    HealthKit import 보다 반드시 먼저 끝내야 — 그래야 import 가 "이미 라벨링한
                    //    워크아웃"임을 알아보고 미라벨 경기로 중복 생성하지 않는다 (기기 재설치 시 중복 큐 방지).
                    await MatchSyncService.shared.restoreLabeledMatches(
                        in: modelContainer.mainContext
                    )

                    // 2) Observer Query 등록 + 즉시 import (ADR-0004 D4).
                    //    권한이 아직 없으면 read 결과 빈 배열 — 권한 허용 후 다음 진입에서 정상 동작.
                    await HealthKitService.shared.startObserver(
                        modelContext: modelContainer.mainContext
                    )

                    // 2.5) 지표 알고리즘 버전업 시 구버전 쿼터 일괄 재분석 (ADR-0012).
                    //      import 이후에 돌아야 신규 쿼터가 이중 분석되지 않는다.
                    await WorkoutAnalyzer.reanalyzeOutdatedQuarters(
                        in: modelContainer.mainContext
                    )

                    // 3) 미동기화 Match 일괄 PUT (ADR-0003 D9 fire-and-forget)
                    await MatchSyncService.shared.syncPending(
                        in: modelContainer.mainContext
                    )
                }
                .onOpenURL { url in
                    if AuthApi.isKakaoTalkLoginUrl(url) {
                        _ = AuthController.handleOpenUrl(url: url)
                    }
                }
        }
        .modelContainer(modelContainer)
        .onChange(of: scenePhase) { _, newPhase in
            // 백그라운드 복귀(.active) 시에도 미동기화 Match 를 재시도한다.
            // 앱 시작 시 1회만 돌던 syncPending 을 foreground 복귀마다 보강 (네트워크 회복 포함).
            guard newPhase == .active else { return }
            Task {
                await MatchSyncService.shared.syncPending(in: modelContainer.mainContext)
            }
        }
    }
}
