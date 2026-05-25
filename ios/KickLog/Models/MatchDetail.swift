import Foundation

// 매치 상세 — 쿼터별 메트릭 포함.
// 더미 단계라 Match 와 1:1 매칭 가정 (matchId 로 lookup).
struct MatchDetail: Hashable {
    let matchId: UUID
    let dateTime: String       // "2026-05-21 (수) 09:00"
    let position: String       // "미드필더 (MF)"
    let positionShort: String  // "MF"
    let goals: Int
    let assists: Int

    // 쿼터별 (Q1~Q4) — 와이어프레임은 정확히 4쿼터
    let speedByQuarter: [Double]      // km/h
    let heartRateByQuarter: [Int]     // bpm
    let sprintsByQuarter: [Int]       // 회

    var quartersPlayed: Int { speedByQuarter.count }
}

extension MatchDetail {
    // matches.jsx 의 첫 번째 행(5/18 FC블루스)와 동일한 더미 detail.
    static func sample(for match: Match) -> MatchDetail {
        MatchDetail(
            matchId: match.id,
            dateTime: "2026-05-21 (수) 09:00",
            position: "미드필더 (MF)",
            positionShort: "MF",
            goals: 2,
            assists: 1,
            speedByQuarter: [7.2, 6.8, 6.5, 6.1],
            heartRateByQuarter: [152, 158, 162, 165],
            sprintsByQuarter: [4, 5, 3, 2]
        )
    }
}
