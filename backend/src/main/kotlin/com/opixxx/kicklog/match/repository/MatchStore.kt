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
    fun findAllByUserIdAndPlayedAtBetween(userId: Long, startInclusive: Instant, endExclusive: Instant): List<Match>
    fun clearVenueId(venueId: Long)
}
