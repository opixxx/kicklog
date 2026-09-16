package com.opixxx.kicklog.match.repository

import com.opixxx.kicklog.match.entity.Match
import java.time.Instant
import java.util.UUID

data class MatchCursorCondition(
    val playedAt: Instant,
    val id: Long,
)

interface MatchStore {
    fun save(match: Match): Match
    fun delete(match: Match)
    fun findById(id: Long): Match?
    fun findByUserIdAndClientMatchId(userId: Long, clientMatchId: UUID): Match?
    fun findAllByUserId(userId: Long, cursor: MatchCursorCondition?, limit: Int): List<Match>
    fun findAllWithQuartersByIdIn(ids: List<Long>): List<Match>
    // 시즌 통계 집계 — 집계 단위별로 나뉘어 있다. matches 와 quarter_workouts 를 조인해
    // 한 번에 집계하면 경기 1행이 쿼터 수만큼 복제되어 값이 중복 합산된다(fan-out).
    fun aggregateSeasonMatches(userId: Long, startInclusive: Instant, endExclusive: Instant): SeasonMatchAggregate
    fun aggregateSeasonQuarters(userId: Long, startInclusive: Instant, endExclusive: Instant): SeasonQuarterAggregate
    fun aggregateMonthlyDistance(userId: Long, startInclusive: Instant, endExclusive: Instant): List<MonthlyDistance>
    fun clearVenueId(venueId: Long)
}
