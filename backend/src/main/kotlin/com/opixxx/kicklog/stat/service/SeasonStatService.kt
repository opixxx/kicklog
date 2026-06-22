package com.opixxx.kicklog.stat.service

import com.opixxx.kicklog.friend.service.FriendshipAuthorizer
import com.opixxx.kicklog.match.entity.Match
import com.opixxx.kicklog.match.repository.MatchStore
import com.opixxx.kicklog.match.service.MatchResultType
import org.springframework.stereotype.Service
import org.springframework.transaction.annotation.Transactional
import java.time.LocalDate
import java.time.ZoneOffset

data class SeasonBest(
    val maxSpeedKmh: Double,
    val longestMatchDistanceM: Int,
    val mostSprintCount: Int,
)

data class SeasonStat(
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
    val monthlyDistanceM: List<Int>,        // 12개. 1월(index 0) ~ 12월(index 11). UTC playedAt 기준.
    val best: SeasonBest,
)

@Service
class SeasonStatService(
    private val matchRepository: MatchStore,
    private val friendshipAuthorizer: FriendshipAuthorizer,
) {
    @Transactional(readOnly = true)
    fun getMySeasonStat(userId: Long, year: Int): SeasonStat {
        return calculate(userId, year)
    }

    @Transactional(readOnly = true)
    fun getFriendSeasonStat(viewerId: Long, friendUserId: Long, year: Int): SeasonStat {
        friendshipAuthorizer.assertCanView(viewerId, friendUserId)
        return calculate(friendUserId, year)
    }

    private fun calculate(userId: Long, year: Int): SeasonStat {
        val matches = findSeasonMatches(userId, year)
        return SeasonStat(
            year = year,
            totalDistanceM = matches.sumOf(Match::totalDistanceM),
            totalGoals = matches.sumOf(Match::goals),
            totalAssists = matches.sumOf(Match::assists),
            matchCount = matches.size,
            quarterCount = matches.sumOf { it.quarters.size },
            winCount = matches.count { it.result == MatchResultType.WIN },
            drawCount = matches.count { it.result == MatchResultType.DRAW },
            lossCount = matches.count { it.result == MatchResultType.LOSS },
            avgHeartRate = weightedAvgHeartRate(matches),
            monthlyDistanceM = monthlyDistance(matches),
            best = best(matches),
        )
    }

    private fun findSeasonMatches(userId: Long, year: Int): List<Match> {
        val start = LocalDate.of(year, 1, 1).atStartOfDay().toInstant(ZoneOffset.UTC)
        val end = LocalDate.of(year + 1, 1, 1).atStartOfDay().toInstant(ZoneOffset.UTC)
        // quarters 는 fetch join 으로 함께 로드된다 (MatchRepository.findAllByUserIdAndPlayedAtBetween).
        return matchRepository.findAllByUserIdAndPlayedAtBetween(userId, start, end)
    }

    // 모든 매치의 모든 쿼터를 duration 가중평균. 쿼터 없거나 총 시간 0이면 0 반환.
    private fun weightedAvgHeartRate(matches: List<Match>): Int {
        val quarters = matches.flatMap { it.quarters }
        val totalDuration = quarters.sumOf { it.durationSeconds.toLong() }
        if (totalDuration == 0L) return 0
        val weighted = quarters.sumOf { it.avgHeartRate.toLong() * it.durationSeconds }
        return (weighted / totalDuration).toInt()
    }

    // playedAt 의 UTC 월(1~12) 기준 groupBy. 결과 List<Int> 는 항상 12개 (빈 월은 0).
    private fun monthlyDistance(matches: List<Match>): List<Int> {
        val arr = IntArray(12)
        matches.forEach { match ->
            val month = match.playedAt.atZone(ZoneOffset.UTC).monthValue
            arr[month - 1] += match.totalDistanceM
        }
        return arr.toList()
    }

    private fun best(matches: List<Match>): SeasonBest {
        return SeasonBest(
            maxSpeedKmh = matches.maxOfOrNull(Match::maxSpeedKmh) ?: 0.0,
            longestMatchDistanceM = matches.maxOfOrNull(Match::totalDistanceM) ?: 0,
            mostSprintCount = matches.maxOfOrNull(Match::sprintCount) ?: 0,
        )
    }
}
