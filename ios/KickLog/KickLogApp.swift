import SwiftUI
import SwiftData

@main
struct KickLogApp: App {
    // ADR-0004 D1 — CloudKit 미사용, 순수 로컬 SwiftData.
    let modelContainer: ModelContainer = {
        do {
            let schema = Schema(KickLogSchema.allModels)
            let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
            return try ModelContainer(for: schema, configurations: config)
        } catch {
            fatalError("ModelContainer 초기화 실패: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            RootView()
                .task {
                    // DEBUG: 시뮬레이터에서 워치 데이터가 없을 때 샘플 주입.
                    #if DEBUG
                    SampleDataSeeder.seedIfNeeded(modelContainer.mainContext)
                    #endif

                    // 앱 진입 시 Observer Query 등록 (ADR-0004 D4).
                    // 권한이 아직 없으면 read 결과 빈 배열 — 권한 허용 후 다음 진입에서 정상 동작.
                    await HealthKitService.shared.startObserver(
                        modelContext: modelContainer.mainContext
                    )
                }
        }
        .modelContainer(modelContainer)
    }
}
