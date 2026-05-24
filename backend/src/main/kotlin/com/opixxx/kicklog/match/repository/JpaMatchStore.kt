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
        return matchRepository.findAllByUserIdAfterCursor(
            userId = userId,
            cursorPlayedAt = cursor?.playedAt,
            cursorId = cursor?.id,
            pageable = PageRequest.of(0, limit),
        )
    }

    override fun findAllByUserIdAndPlayedAtBetween(
        userId: Long,
        startInclusive: Instant,
        endExclusive: Instant,
    ): List<Match> {
        return matchRepository.findAllByUserIdAndPlayedAtBetween(userId, startInclusive, endExclusive)
    }
}
