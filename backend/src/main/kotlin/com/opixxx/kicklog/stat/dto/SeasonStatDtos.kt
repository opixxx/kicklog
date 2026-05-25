package com.opixxx.kicklog.stat.dto

import com.opixxx.kicklog.stat.service.SeasonBest
import com.opixxx.kicklog.stat.service.SeasonStat

data class SeasonStatResponse(
    val year: Int,
    val totalDistanceM: Int,
    val totalGoals: Int,
    val totalAssists: Int,
    val matchCount: Int,
    val quarterCount: Int,
    val winCount: Int,
    val drawCount: Int,
    val lossCount: Int,
    val avgHeartRate: Int,
    val monthlyDistanceM: List<Int>,
    val best: SeasonBestResponse,
) {
    companion object {
        fun from(stat: SeasonStat): SeasonStatResponse {
            return SeasonStatResponse(
                year = stat.year,
                totalDistanceM = stat.totalDistanceM,
                totalGoals = stat.totalGoals,
                totalAssists = stat.totalAssists,
                matchCount = stat.matchCount,
                quarterCount = stat.quarterCount,
                winCount = stat.winCount,
                drawCount = stat.drawCount,
                lossCount = stat.lossCount,
                avgHeartRate = stat.avgHeartRate,
                monthlyDistanceM = stat.monthlyDistanceM,
                best = SeasonBestResponse.from(stat.best),
            )
        }
    }
}

data class SeasonBestResponse(
    val maxSpeedKmh: Double,
    val longestMatchDistanceM: Int,
    val mostSprintCount: Int,
) {
    companion object {
        fun from(best: SeasonBest): SeasonBestResponse {
            return SeasonBestResponse(
                maxSpeedKmh = best.maxSpeedKmh,
                longestMatchDistanceM = best.longestMatchDistanceM,
                mostSprintCount = best.mostSprintCount,
            )
        }
    }
}
