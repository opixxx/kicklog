package com.opixxx.kicklog.match.service

enum class MatchResultType {
    WIN,
    DRAW,
    LOSS,

    ;

    companion object {
        // 팀 골 vs 상대 골 비교로 매치 결과를 도출한다.
        // 한 쪽이라도 null 이면 결과를 결정할 수 없으므로 null.
        fun derive(teamGoals: Int?, opponentGoals: Int?): MatchResultType? {
            if (teamGoals == null || opponentGoals == null) return null
            return when {
                teamGoals > opponentGoals -> WIN
                teamGoals < opponentGoals -> LOSS
                else -> DRAW
            }
        }
    }
}

enum class MatchPosition {
    GK,
    DF,
    MF,
    FW,
}
