package com.opixxx.kicklog.stat.service

import com.opixxx.kicklog.friend.service.FriendshipAuthorizer
import com.opixxx.kicklog.match.entity.Match
import com.opixxx.kicklog.match.repository.MatchStore
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
            best = best(matches),
        )
    }

    private fun findSeasonMatches(userId: Long, year: Int): List<Match> {
        val start = LocalDate.of(year, 1, 1).atStartOfDay().toInstant(ZoneOffset.UTC)
        val end = LocalDate.of(year + 1, 1, 1).atStartOfDay().toInstant(ZoneOffset.UTC)
        return matchRepository.findAllByUserIdAndPlayedAtBetween(userId, start, end).onEach { it.quarters.size }
    }

    private fun best(matches: List<Match>): SeasonBest {
        return SeasonBest(
            maxSpeedKmh = matches.maxOfOrNull(Match::maxSpeedKmh) ?: 0.0,
            longestMatchDistanceM = matches.maxOfOrNull(Match::totalDistanceM) ?: 0,
            mostSprintCount = matches.maxOfOrNull(Match::sprintCount) ?: 0,
        )
    }
}
