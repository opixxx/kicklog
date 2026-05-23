package com.opixxx.kicklog.match.service

import com.opixxx.kicklog.common.dto.CursorResponse
import com.opixxx.kicklog.common.exception.ErrorCode
import com.opixxx.kicklog.common.exception.KickLogException
import com.opixxx.kicklog.match.entity.Match
import com.opixxx.kicklog.match.repository.MatchStore
import com.opixxx.kicklog.venue.repository.VenueStore
import org.springframework.stereotype.Service
import org.springframework.transaction.annotation.Transactional
import java.util.UUID
import kotlin.math.min

data class SaveMatchResult(
    val match: Match,
    val updated: Boolean,
)

@Service
class MatchService(
    private val matchRepository: MatchStore,
    private val venueRepository: VenueStore,
) {
    @Transactional
    fun saveMatch(userId: Long, clientMatchId: UUID, command: UpsertMatchCommand): SaveMatchResult {
        validateVenue(userId, command.venueId)
        val existing = matchRepository.findByUserIdAndClientMatchId(userId, clientMatchId)
        if (existing != null) {
            existing.replaceWith(command)
            return SaveMatchResult(initialize(matchRepository.save(existing)), updated = true)
        }

        return SaveMatchResult(
            initialize(matchRepository.save(Match.create(userId, clientMatchId, command))),
            updated = false,
        )
    }

    @Transactional(readOnly = true)
    fun getMyMatch(userId: Long, matchId: Long): Match {
        val match = matchRepository.findById(matchId)
            ?: throw KickLogException(ErrorCode.MATCH_NOT_FOUND)
        if (match.userId != userId) {
            throw KickLogException(ErrorCode.MATCH_NOT_OWNED)
        }
        return initialize(match)
    }

    @Transactional(readOnly = true)
    fun getMyMatchByClientId(userId: Long, clientMatchId: UUID): Match {
        val match = matchRepository.findByUserIdAndClientMatchId(userId, clientMatchId)
            ?: throw KickLogException(ErrorCode.MATCH_NOT_FOUND)
        return initialize(match)
    }

    @Transactional
    fun deleteMyMatch(userId: Long, matchId: Long) {
        val match = matchRepository.findById(matchId)
            ?: throw KickLogException(ErrorCode.MATCH_NOT_FOUND)
        if (match.userId != userId) {
            throw KickLogException(ErrorCode.MATCH_NOT_OWNED)
        }
        matchRepository.delete(match)
    }

    @Transactional(readOnly = true)
    fun listMyMatches(userId: Long, cursor: String?, size: Int): CursorResponse<Match> {
        val normalizedSize = min(size.coerceAtLeast(1), MAX_PAGE_SIZE)
        val matches = matchRepository.findAllByUserId(
            userId = userId,
            cursor = MatchCursor.decode(cursor),
            limit = normalizedSize + 1,
        )
        matches.forEach(::initialize)
        return toCursorResponse(matches, normalizedSize)
    }

    private fun validateVenue(userId: Long, venueId: Long) {
        val venue = venueRepository.findById(venueId)
            ?: throw KickLogException(ErrorCode.VENUE_NOT_FOUND)
        if (venue.userId != userId) {
            throw KickLogException(ErrorCode.VENUE_NOT_OWNED)
        }
    }

    private fun toCursorResponse(matches: List<Match>, size: Int): CursorResponse<Match> {
        val content = matches.take(size)
        val hasNext = matches.size > size
        val nextCursor = if (hasNext) {
            content.lastOrNull()?.let { MatchCursor.encode(it.playedAt, it.id) }
        } else {
            null
        }
        return CursorResponse(content = content, size = size, nextCursor = nextCursor, hasNext = hasNext)
    }

    private fun initialize(match: Match): Match {
        match.quarters.size
        return match
    }

    companion object {
        private const val MAX_PAGE_SIZE = 100
    }
}
