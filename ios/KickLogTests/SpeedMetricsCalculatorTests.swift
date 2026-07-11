import Foundation
import Testing
@testable import KickLog

// ADR-0012 — 속도 정제 파이프라인 + 스프린트/고강도 러닝 재설계 검증.
// 실측 픽스처: 2026-05-28 3쿼터 + 2024-05-01 저밀도 워크아웃 (애플 건강 export 에서 추출).
// 기대치는 확정 설계 레퍼런스 구현(ref_final.py, 세션 scratchpad)으로 산출.

private final class FixtureBundleToken {}

private func loadFixture(_ name: String) throws -> (distance: [SpeedMetricsCalculator.DistanceSample],
                                                    heartRate: [SpeedMetricsCalculator.HeartRateSample]) {
    let bundle = Bundle(for: FixtureBundleToken.self)

    func rows(_ resource: String) throws -> [[String]] {
        guard let url = bundle.url(forResource: resource, withExtension: "csv") else {
            throw NSError(domain: "fixture", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "픽스처 없음: \(resource).csv"])
        }
        let text = try String(contentsOf: url, encoding: .utf8)
        return text.split(separator: "\n").dropFirst().map { $0.split(separator: ",").map(String.init) }
    }

    let distance = try rows("\(name)_distance").map {
        SpeedMetricsCalculator.DistanceSample(start: Double($0[0])!, duration: Double($0[1])!, meters: Double($0[2])!)
    }
    let heartRate = try rows("\(name)_heartrate").map {
        SpeedMetricsCalculator.HeartRateSample(time: Double($0[0])!, bpm: Double($0[1])!)
    }
    return (distance, heartRate)
}

// 합성 샘플 헬퍼 — kmh 속도가 되도록 meters 역산 (dur 3초 기본)
private func sample(t: Double, kmh: Double, dur: Double = 3) -> SpeedMetricsCalculator.DistanceSample {
    SpeedMetricsCalculator.DistanceSample(start: t, duration: dur, meters: kmh / 3.6 * dur)
}

struct SpeedMetricsCalculatorTests {
    let calc = SpeedMetricsCalculator()

    // MARK: - Happy: 실측 재현 (인수 테스트)

    @Test("Q1 실측 — 33.0 고립 스파이크 기각, 정지 출발 램프(28.5) 유지")
    func q1RealData() throws {
        let (dist, hr) = try loadFixture("q1_20260528")
        let m = calc.calculate(distance: dist, heartRate: hr, analysisDuration: 1558)
        #expect(m.available)
        #expect(abs(m.maxSpeedKmh - 28.5) < 0.1)
        #expect(m.sprintCount == 7)
        #expect(m.highIntensityRunCount == 25)
    }

    @Test("Q2 실측 — 공백 옆 34.1 이 심박 급등(+15bpm)으로 유지")
    func q2RealData() throws {
        let (dist, hr) = try loadFixture("q2_20260528")
        let m = calc.calculate(distance: dist, heartRate: hr, analysisDuration: 1273)
        #expect(m.available)
        #expect(abs(m.maxSpeedKmh - 34.1) < 0.1)
        #expect(m.sprintCount == 13)
        #expect(m.highIntensityRunCount == 25)
    }

    @Test("Q3 실측 — 후반 고심박(세션 최고 95%) 규칙으로 27.8·26.2 스프린트 유지, max 는 29.4")
    func q3RealData() throws {
        let (dist, hr) = try loadFixture("q3_20260528")
        let m = calc.calculate(distance: dist, heartRate: hr, analysisDuration: 1443)
        #expect(m.available)
        #expect(abs(m.maxSpeedKmh - 29.4) < 0.1)
        #expect(m.sprintCount == 16)
        #expect(m.highIntensityRunCount == 28)
    }

    @Test("정지 출발 단일 샘플 스프린트 — 양옆 공백 + 심박 급등 → 유지")
    func standingStartSprintSurvives() {
        let dist = [sample(t: 0, kmh: 4), sample(t: 9, kmh: 20.5), sample(t: 18, kmh: 4)]
        let hr = (0...11).map { SpeedMetricsCalculator.HeartRateSample(time: Double($0), bpm: 150) }
            + [.init(time: 15, bpm: 160), .init(time: 25, bpm: 172), .init(time: 40, bpm: 175)]
        let m = calc.calculate(distance: dist, heartRate: hr, analysisDuration: 21)
        #expect(m.sprintCount == 1)
        #expect(abs(m.maxSpeedKmh - 20.5) < 0.01)
    }

    @Test("히스테리시스 — 질주 중 18km/h 출렁임은 같은 스프린트 (쪼개지지 않음)")
    func hysteresisKeepsSingleSprint() {
        let dist = [sample(t: 0, kmh: 21), sample(t: 3, kmh: 18), sample(t: 6, kmh: 21)]
        let m = calc.calculate(distance: dist, heartRate: [], analysisDuration: 9)
        #expect(m.sprintCount == 1)
    }

    @Test("고강도 러닝 — 14~16km/h 연속 구간은 HSR 1회, 스프린트 0회")
    func highIntensityRunCountedSeparately() {
        let dist = [sample(t: 0, kmh: 15), sample(t: 3, kmh: 15.5), sample(t: 6, kmh: 16)]
        let m = calc.calculate(distance: dist, heartRate: [], analysisDuration: 9)
        #expect(m.highIntensityRunCount == 1)
        #expect(m.sprintCount == 0)
        #expect(abs(m.maxSpeedKmh - 16) < 0.01)
    }

    // MARK: - Unhappy: 노이즈 기각

    @Test("고립 스파이크 — 양옆이 걷기 속도면 물리적으로 불가능 → 기각")
    func isolatedSpikeRejected() {
        let dist = [sample(t: 0, kmh: 5), sample(t: 3, kmh: 33), sample(t: 6, kmh: 5)]
        let m = calc.calculate(distance: dist, heartRate: [], analysisDuration: 9)
        #expect(m.sprintCount == 0)
        #expect(abs(m.maxSpeedKmh - 5) < 0.01)
    }

    @Test("35km/h 초과 — 초대형 GPS 점프는 시계열에서 제거")
    func capFiltersImpossibleSpeed() {
        let dist = [sample(t: 0, kmh: 10), sample(t: 3, kmh: 51.4), sample(t: 6, kmh: 10)]
        let m = calc.calculate(distance: dist, heartRate: [], analysisDuration: 9)
        #expect(abs(m.maxSpeedKmh - 10) < 0.01)
        #expect(m.sprintCount == 0)
    }

    @Test("공백 옆 스파이크 + 심박 평탄 → 기각")
    func ambiguousSpikeWithFlatHeartRateRejected() {
        let dist = [sample(t: 0, kmh: 4), sample(t: 9, kmh: 25), sample(t: 18, kmh: 4)]
        let hr = (0...60).map { SpeedMetricsCalculator.HeartRateSample(time: Double($0), bpm: 150) }
        let m = calc.calculate(distance: dist, heartRate: hr, analysisDuration: 21)
        #expect(m.sprintCount == 0)
        #expect(abs(m.maxSpeedKmh - 4) < 0.01)
    }

    @Test("공백 옆 스파이크 + 심박 데이터 없음 → 보수적으로 기각")
    func ambiguousSpikeWithoutHeartRateRejected() {
        let dist = [sample(t: 0, kmh: 4), sample(t: 9, kmh: 25), sample(t: 18, kmh: 4)]
        let m = calc.calculate(distance: dist, heartRate: [], analysisDuration: 21)
        #expect(m.sprintCount == 0)
        #expect(abs(m.maxSpeedKmh - 4) < 0.01)
    }

    // MARK: - Edge

    @Test("샘플 공백 3초 초과 — 질주(run)가 분리되어 2회로 집계")
    func gapSplitsRuns() {
        let dist = [
            sample(t: 0, kmh: 21), sample(t: 3, kmh: 21),
            sample(t: 14, kmh: 21), sample(t: 17, kmh: 21),
        ]
        let m = calc.calculate(distance: dist, heartRate: [], analysisDuration: 20)
        #expect(m.sprintCount == 2)
    }

    @Test("저밀도 실측(2024-05-01, 중앙값 541초 뭉텅이) → 계산 불가")
    func sparseRealDataUnavailable() throws {
        let (dist, hr) = try loadFixture("sparse_20240501")
        let m = calc.calculate(distance: dist, heartRate: hr, analysisDuration: 6339)
        #expect(!m.available)
        #expect(m.maxSpeedKmh == 0)
        #expect(m.sprintCount == 0)
        #expect(m.highIntensityRunCount == 0)
    }

    @Test("커버리지 30% 미만 — 짧은 샘플이라도 관측 구간이 너무 성기면 계산 불가")
    func lowCoverageUnavailable() {
        let dist = [sample(t: 0, kmh: 10)]
        let m = calc.calculate(distance: dist, heartRate: [], analysisDuration: 60)
        #expect(!m.available)
    }

    @Test("빈 샘플 → 계산 불가 + 전 지표 0")
    func emptySamplesUnavailable() {
        let m = calc.calculate(distance: [], heartRate: [], analysisDuration: 600)
        #expect(!m.available)
        #expect(m.avgSpeedKmh == 0)
        #expect(m.maxSpeedKmh == 0)
    }

    @Test("계산 불가여도 평균 속도는 유효 (뭉텅이 샘플의 거리/시간은 신뢰 가능)")
    func avgSpeedStillComputedWhenUnavailable() throws {
        let (dist, hr) = try loadFixture("sparse_20240501")
        let m = calc.calculate(distance: dist, heartRate: hr, analysisDuration: 6339)
        #expect(m.avgSpeedKmh > 1)
    }
}

// MARK: - 소스 필터 (거리 이중 집계 방지)

struct SampleSourceFilterTests {
    @Test("Watch 소스 존재 시 Watch 샘플만 사용 — iPhone 동시 기록분 제외")
    func watchOnlyWhenMixed() {
        let sources: [String?] = ["iPhone14,2", "Watch6,7", nil, "Watch6,7"]
        let picked = SampleSourceFilter.primary(Array(sources.indices), productType: { sources[$0] })
        #expect(picked == [1, 3])
    }

    @Test("Watch 소스 부재 시 전체 사용 (단일 소스 기록 보존)")
    func allWhenNoWatch() {
        let sources: [String?] = ["iPhone14,2", "iPhone14,2", nil]
        let picked = SampleSourceFilter.primary(Array(sources.indices), productType: { sources[$0] })
        #expect(picked == [0, 1, 2])
    }
}
