package com.opixxx.kicklog.match.repository

import com.opixxx.kicklog.match.entity.Match
import java.time.Instant
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

    override fun findAllByUserIdAndPlayedAtBetween(
        userId: Long,
        startInclusive: Instant,
        endExclusive: Instant,
    ): List<Match> {
        return matches.values
            .filter { it.userId == userId }
            .filter { !it.playedAt.isBefore(startInclusive) && it.playedAt.isBefore(endExclusive) }
            .sortedWith(compareByDescending<Match> { it.playedAt }.thenByDescending { it.id })
    }

    override fun clearVenueId(venueId: Long) {
        matches.values.filter { it.venueId == venueId }.forEach { it.venueId = null }
    }

    fun count(): Int = matches.size
}
