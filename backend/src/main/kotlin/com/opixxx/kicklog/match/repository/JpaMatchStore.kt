package com.opixxx.kicklog.match.repository

import com.opixxx.kicklog.match.entity.Match
import org.springframework.data.domain.PageRequest
import org.springframework.stereotype.Repository
import java.time.Instant
import java.util.UUID

@Repository
class JpaMatchStore(
    private val matchRepository: MatchRepository,
) : MatchStore {
    override fun save(match: Match): Match = matchRepository.save(match)

    override fun delete(match: Match) {
        matchRepository.delete(match)
    }

    override fun findById(id: Long): Match? = matchRepository.findById(id).orElse(null)

    override fun findByUserIdAndClientMatchId(userId: Long, clientMatchId: UUID): Match? {
        return matchRepository.findByUserIdAndClientMatchId(userId, clientMatchId)
    }

    override fun findAllByUserId(userId: Long, cursor: MatchCursorCondition?, limit: Int): List<Match> {
        val pageable = PageRequest.of(0, limit)
        return if (cursor == null) {
            matchRepository.findFirstPageByUserId(userId = userId, pageable = pageable)
        } else {
            matchRepository.findAllByUserIdAfterCursor(
                userId = userId,
                cursorPlayedAt = cursor.playedAt,
                cursorId = cursor.id,
                pageable = pageable,
            )
        }
    }

    override fun findAllWithQuartersByIdIn(ids: List<Long>): List<Match> {
        if (ids.isEmpty()) return emptyList()
        return matchRepository.findAllWithQuartersByIdIn(ids)
    }

    // DB 집계는 bigint 로 오고 도메인은 Int 다. toInt() 는 초과 시 조용히 wrap 하므로
    // toIntExact 로 즉시 예외를 낸다 — 통계가 음수로 뒤집히는 것보다 실패가 낫다.
    override fun aggregateSeasonMatches(
        userId: Long,
        startInclusive: Instant,
        endExclusive: Instant,
    ): SeasonMatchAggregate {
        val row = matchRepository.aggregateSeasonMatches(userId, startInclusive, endExclusive)
        return SeasonMatchAggregate(
            totalDistanceM = Math.toIntExact(row.totalDistanceM),
            totalGoals = Math.toIntExact(row.totalGoals),
            totalAssists = Math.toIntExact(row.totalAssists),
            matchCount = Math.toIntExact(row.matchCount),
            winCount = Math.toIntExact(row.winCount),
            drawCount = Math.toIntExact(row.drawCount),
            lossCount = Math.toIntExact(row.lossCount),
            maxSpeedKmh = row.maxSpeedKmh,
            longestMatchDistanceM = Math.toIntExact(row.longestMatchDistanceM),
            mostSprintCount = Math.toIntExact(row.mostSprintCount),
        )
    }

    override fun aggregateSeasonQuarters(
        userId: Long,
        startInclusive: Instant,
        endExclusive: Instant,
    ): SeasonQuarterAggregate {
        val row = matchRepository.aggregateSeasonQuarters(userId, startInclusive, endExclusive)
        return SeasonQuarterAggregate(
            quarterCount = Math.toIntExact(row.quarterCount),
            weightedHeartRateSum = row.weightedHeartRateSum,
            totalDurationSeconds = row.totalDurationSeconds,
        )
    }

    override fun aggregateMonthlyDistance(
        userId: Long,
        startInclusive: Instant,
        endExclusive: Instant,
    ): List<MonthlyDistance> {
        return matchRepository.aggregateMonthlyDistance(userId, startInclusive, endExclusive)
            .map { MonthlyDistance(month = it.month, distanceM = Math.toIntExact(it.distanceM)) }
    }

    override fun clearVenueId(venueId: Long) {
        matchRepository.clearVenueId(venueId)
    }
}
