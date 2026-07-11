import Foundation
import HealthKit
import SwiftData

// ADR-0004 D3 — HealthKit 권한 set 6개.
// D4 — HKObserverQuery + Background Delivery 로 새 Soccer 워크아웃 자동 import.
@MainActor
final class HealthKitService {
    static let shared = HealthKitService()

    let store = HKHealthStore()
    private var observerQuery: HKObserverQuery?

    // ModelContainer 가 등록된 후 startObserver 호출 시 주입받는다.
    private var importer: WorkoutImporter?

    // ADR-0004 D3 최소 권한 — runningSpeed read 는 ADR-0012 에서 분석 경로 제거와 함께 삭제
    // (축구 워크아웃엔 해당 샘플이 아예 없음. DEBUG 시드용 write 권한은 별개로 유지)
    static let readTypes: Set<HKObjectType> = [
        HKObjectType.workoutType(),
        HKQuantityType(.heartRate),
        HKQuantityType(.distanceWalkingRunning),
        HKQuantityType(.activeEnergyBurned),
        HKSeriesType.workoutRoute(),
    ]

    // DEBUG 빌드 전용 — E2E 테스트용 워크아웃 시드를 위한 share(write) 권한.
    // 릴리즈 빌드에서는 빈 set 으로 권한 다이얼로그에 노출되지 않는다.
    static let writeTypes: Set<HKSampleType> = {
        #if DEBUG
        return [
            HKObjectType.workoutType(),
            HKQuantityType(.heartRate),
            HKQuantityType(.distanceWalkingRunning),
            HKQuantityType(.activeEnergyBurned),
            HKQuantityType(.runningSpeed),
            HKSeriesType.workoutRoute(),
        ]
        #else
        return []
        #endif
    }()

    enum AuthorizationStatus {
        case notDetermined
        case authorized          // 권한 화면 한 번 본 상태 (Apple 정책상 read 권한은 share status 로만 확인 가능)
        case unavailable         // 디바이스가 HealthKit 미지원
    }

    private init() {}

    var isHealthDataAvailable: Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    // 권한 다이얼로그 표시.
    // 주의: HealthKit read 권한은 Apple 정책상 "사용자가 허용했는지" 직접 확인 불가 — 데이터를 실제 쿼리해서 빈 결과인지로 추론해야 한다 (Phase B 에서 처리).
    func requestAuthorization() async throws {
        guard isHealthDataAvailable else { throw HealthKitError.notAvailable }
        try await store.requestAuthorization(toShare: Self.writeTypes, read: Self.readTypes)
    }

    // 한 번이라도 권한 화면을 표시했는지 (NotDetermined 가 아닌지) 추론.
    // workoutType 의 share status 로 확인 — read-only 권한이라 항상 sharingDenied 지만,
    // notDetermined 상태와는 구분된다.
    func hasPromptedAuthorization() -> Bool {
        guard isHealthDataAvailable else { return false }
        let status = store.authorizationStatus(for: .workoutType())
        return status != .notDetermined
    }

    // MARK: - Observer Query + Background Delivery (ADR-0004 D4)

    // 앱 시작 시 호출. 새 Soccer 워크아웃 발생 시 백그라운드 import 트리거.
    func startObserver(modelContext: ModelContext) async {
        guard isHealthDataAvailable else { return }

        // 기존 observer 가 있으면 stop (중복 방지)
        if let existing = observerQuery {
            store.stop(existing)
            observerQuery = nil
        }

        let importer = WorkoutImporter(store: store, modelContext: modelContext)
        self.importer = importer

        // 1. 앱 진입 시 1회 즉시 import (놓친 워크아웃 따라잡기)
        await importer.importNewSoccerWorkouts()

        // 2. Observer 등록 — 새 워크아웃 발생 시 트리거
        let workoutType = HKObjectType.workoutType()
        let observer = HKObserverQuery(sampleType: workoutType, predicate: nil) { [weak self] _, completion, error in
            if let error {
                print("HKObserverQuery error: \(error)")
                completion()
                return
            }
            Task { @MainActor [weak self] in
                await self?.importer?.importNewSoccerWorkouts()
                completion()
            }
        }
        store.execute(observer)
        observerQuery = observer

        // 3. Background Delivery — system event 기반, 배터리 영향 미미
        do {
            try await store.enableBackgroundDelivery(for: workoutType, frequency: .immediate)
        } catch {
            print("enableBackgroundDelivery 실패: \(error)")
        }
    }
}

enum HealthKitError: LocalizedError {
    case notAvailable
    case authorizationDenied
    case queryFailed(underlying: Error)

    var errorDescription: String? {
        switch self {
        case .notAvailable:
            return "이 디바이스에서는 HealthKit 을 사용할 수 없습니다."
        case .authorizationDenied:
            return "건강 데이터 권한이 거부되었습니다. 설정 → 건강 → 데이터 접근 및 기기 → KickLog 에서 허용해주세요."
        case .queryFailed(let underlying):
            return "건강 데이터 조회 중 오류: \(underlying.localizedDescription)"
        }
    }
}
