package com.opixxx.kicklog.match.service

import com.opixxx.kicklog.common.dto.CursorResponse
import com.opixxx.kicklog.common.exception.ErrorCode
import com.opixxx.kicklog.common.exception.KickLogException
import com.opixxx.kicklog.friend.service.FriendshipAuthorizer
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
    private val friendshipAuthorizer: FriendshipAuthorizer,
) {
    @Transactional
    fun saveMatch(userId: Long, clientMatchId: UUID, command: UpsertMatchCommand): SaveMatchResult {
        validateVenue(userId, command.venueId)
        val existing = matchRepository.findByUserIdAndClientMatchId(userId, clientMatchId)
        if (existing != null) {
            existing.replaceWith(command)
            // 저장 직후 quarters 는 영속 컨텍스트에 in-memory 로 존재 — 추가 조회 불필요.
            return SaveMatchResult(matchRepository.save(existing), updated = true)
        }

        return SaveMatchResult(
            matchRepository.save(Match.create(userId, clientMatchId, command)),
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
        return withQuarters(match)
    }

    @Transactional(readOnly = true)
    fun getMyMatchByClientId(userId: Long, clientMatchId: UUID): Match {
        val match = matchRepository.findByUserIdAndClientMatchId(userId, clientMatchId)
            ?: throw KickLogException(ErrorCode.MATCH_NOT_FOUND)
        return withQuarters(match)
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
        return listMatchesByUser(userId, cursor, size)
    }

    @Transactional(readOnly = true)
    fun listFriendMatches(viewerId: Long, friendUserId: Long, cursor: String?, size: Int): CursorResponse<Match> {
        friendshipAuthorizer.assertCanView(viewerId, friendUserId)
        return listMatchesByUser(friendUserId, cursor, size)
    }

    @Transactional(readOnly = true)
    fun getFriendMatch(viewerId: Long, friendUserId: Long, matchId: Long): Match {
        friendshipAuthorizer.assertCanView(viewerId, friendUserId)
        val match = matchRepository.findById(matchId)
            ?: throw KickLogException(ErrorCode.MATCH_NOT_FOUND)
        if (match.userId != friendUserId) {
            throw KickLogException(ErrorCode.MATCH_NOT_FOUND)
        }
        return withQuarters(match)
    }

    private fun listMatchesByUser(userId: Long, cursor: String?, size: Int): CursorResponse<Match> {
        val normalizedSize = min(size.coerceAtLeast(1), MAX_PAGE_SIZE)
        // 1단계: id 페이징 (커서 쿼리 — 컬렉션 fetch join 시 메모리 페이징 발생하므로 분리).
        val paged = matchRepository.findAllByUserId(
            userId = userId,
            cursor = MatchCursor.decode(cursor),
            limit = normalizedSize + 1,
        )
        // 2단계: quarters fetch join 재조회 (N+1 제거, 정렬은 재조회 쿼리가 보장).
        val matches = matchRepository.findAllWithQuartersByIdIn(paged.map(Match::id))
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

    // 단건 응답용 — quarters 를 fetch join 으로 재조회해 OSIV off 환경에서도 detached 접근 안전.
    private fun withQuarters(match: Match): Match {
        return matchRepository.findAllWithQuartersByIdIn(listOf(match.id)).firstOrNull() ?: match
    }

    companion object {
        private const val MAX_PAGE_SIZE = 100
    }
}
