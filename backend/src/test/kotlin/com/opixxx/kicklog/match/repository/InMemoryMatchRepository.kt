package com.opixxx.kicklog.match.repository

import com.opixxx.kicklog.match.entity.Match
import com.opixxx.kicklog.match.service.MatchResultType
import java.time.Instant
import java.time.ZoneOffset
import java.util.UUID

class InMemoryMatchRepository : MatchStore {
    private val matches = linkedMapOf<Long, Match>()
    private var sequence = 1L

    override fun save(match: Match): Match {
        if (match.id == 0L) {
            match.id = sequence++
        }
        matches[match.id] = match
        return match
    }

    override fun delete(match: Match) {
        matches.remove(match.id)
    }

    override fun findById(id: Long): Match? = matches[id]

    override fun findByUserIdAndClientMatchId(userId: Long, clientMatchId: UUID): Match? {
        return matches.values.firstOrNull { it.userId == userId && it.clientMatchId == clientMatchId }
    }

    override fun findAllByUserId(userId: Long, cursor: MatchCursorCondition?, limit: Int): List<Match> {
        return matches.values
            .filter { it.userId == userId }
            .sortedWith(compareByDescending<Match> { it.playedAt }.thenByDescending { it.id })
            .filter { cursor == null || it.playedAt < cursor.playedAt || it.playedAt == cursor.playedAt && it.id < cursor.id }
            .take(limit)
    }

    override fun findAllWithQuartersByIdIn(ids: List<Long>): List<Match> {
        val idSet = ids.toSet()
        return matches.values
            .filter { it.id in idSet }
            .sortedWith(compareByDescending<Match> { it.playedAt }.thenByDescending { it.id })
    }

    // ─── 시즌 집계 — 참조 구현 ──────────────────────────────────────
    // JpaMatchStore 의 집계 SQL 과 **같은 값**을 내야 한다. 전환 전 SeasonStatService 가
    // 하던 계산을 그대로 옮겨온 것이라, 기존 단위 테스트가 이 구현으로 통과하면 동작 보존이 증명된다.

    private fun seasonMatches(userId: Long, startInclusive: Instant, endExclusive: Instant): List<Match> {
        return matches.values
            .filter { it.userId == userId }
            .filter { !it.playedAt.isBefore(startInclusive) && it.playedAt.isBefore(endExclusive) }
    }

    override fun aggregateSeasonMatches(
        userId: Long,
        startInclusive: Instant,
        endExclusive: Instant,
    ): SeasonMatchAggregate {
        val seasonMatches = seasonMatches(userId, startInclusive, endExclusive)
        if (seasonMatches.isEmpty()) return SeasonMatchAggregate.EMPTY
        return SeasonMatchAggregate(
            totalDistanceM = seasonMatches.sumOf(Match::totalDistanceM),
            totalGoals = seasonMatches.sumOf(Match::goals),
            totalAssists = seasonMatches.sumOf(Match::assists),
            matchCount = seasonMatches.size,
            winCount = seasonMatches.count { it.result == MatchResultType.WIN },
            drawCount = seasonMatches.count { it.result == MatchResultType.DRAW },
            lossCount = seasonMatches.count { it.result == MatchResultType.LOSS },
            maxSpeedKmh = seasonMatches.maxOf(Match::maxSpeedKmh),
            longestMatchDistanceM = seasonMatches.maxOf(Match::totalDistanceM),
            mostSprintCount = seasonMatches.maxOf(Match::sprintCount),
        )
    }

    override fun aggregateSeasonQuarters(
        userId: Long,
        startInclusive: Instant,
        endExclusive: Instant,
    ): SeasonQuarterAggregate {
        val quarters = seasonMatches(userId, startInclusive, endExclusive).flatMap { it.quarters }
        if (quarters.isEmpty()) return SeasonQuarterAggregate.EMPTY
        return SeasonQuarterAggregate(
            quarterCount = quarters.size,
            weightedHeartRateSum = quarters.sumOf { it.avgHeartRate.toLong() * it.durationSeconds },
            totalDurationSeconds = quarters.sumOf { it.durationSeconds.toLong() },
        )
    }

    override fun aggregateMonthlyDistance(
        userId: Long,
        startInclusive: Instant,
        endExclusive: Instant,
    ): List<MonthlyDistance> {
        // UTC 월 기준 — api-spec §8.1. 데이터 있는 달만 반환한다 (12칸 채우기는 호출부 책임).
        return seasonMatches(userId, startInclusive, endExclusive)
            .groupBy { it.playedAt.atZone(ZoneOffset.UTC).monthValue }
            .map { (month, monthMatches) -> MonthlyDistance(month, monthMatches.sumOf(Match::totalDistanceM)) }
            .sortedBy { it.month }
    }

    override fun clearVenueId(venueId: Long) {
        matches.values.filter { it.venueId == venueId }.forEach { it.venueId = null }
    }

    fun count(): Int = matches.size
}
