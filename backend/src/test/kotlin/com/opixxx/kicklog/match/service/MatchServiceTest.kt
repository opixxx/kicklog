package com.opixxx.kicklog.match.service

import com.opixxx.kicklog.common.exception.ErrorCode
import com.opixxx.kicklog.common.exception.KickLogException
import com.opixxx.kicklog.match.repository.InMemoryMatchRepository
import com.opixxx.kicklog.venue.entity.Venue
import com.opixxx.kicklog.venue.repository.InMemoryVenueRepository
import java.math.BigDecimal
import java.time.Instant
import java.util.UUID
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertNotNull
import kotlin.test.assertNull

class MatchServiceTest {

    private val matchRepository = InMemoryMatchRepository()
    private val venueRepository = InMemoryVenueRepository()
    private val service = MatchService(matchRepository, venueRepository)

    @Test
    fun `경기를 신규 저장한다`() {
        val venue = saveVenue(userId = 1L)
        val result = service.saveMatch(1L, CLIENT_MATCH_ID, command(venue.id))

        assertEquals(false, result.updated)
        assertEquals(CLIENT_MATCH_ID, result.match.clientMatchId)
        assertEquals(1, result.match.quarters.size)
    }

    @Test
    fun `같은 사용자와 clientMatchId면 기존 경기를 덮어쓴다`() {
        val venue = saveVenue(userId = 1L)
        service.saveMatch(1L, CLIENT_MATCH_ID, command(venue.id, goals = 1, workoutId = "hk-old"))

        val result = service.saveMatch(1L, CLIENT_MATCH_ID, command(venue.id, goals = 2, workoutId = "hk-new"))

        assertEquals(true, result.updated)
        assertEquals(1, matchRepository.count())
        assertEquals(2, result.match.goals)
        assertEquals("hk-new", result.match.quarters.single().healthKitWorkoutId)
    }

    @Test
    fun `다른 사용자의 운동장에는 저장할 수 없다`() {
        val venue = saveVenue(userId = 2L)

        val exception = assertFailsWith<KickLogException> {
            service.saveMatch(1L, CLIENT_MATCH_ID, command(venue.id))
        }

        assertEquals(ErrorCode.VENUE_NOT_OWNED, exception.errorCode)
    }

    @Test
    fun `없는 운동장에는 저장할 수 없다`() {
        val exception = assertFailsWith<KickLogException> {
            service.saveMatch(1L, CLIENT_MATCH_ID, command(999L))
        }

        assertEquals(ErrorCode.VENUE_NOT_FOUND, exception.errorCode)
    }

    @Test
    fun `목록은 최신순 cursor 방식으로 다음 페이지를 만든다`() {
        val venue = saveVenue(userId = 1L)
        service.saveMatch(1L, UUID.fromString("00000000-0000-0000-0000-000000000001"), command(venue.id, playedAt = "2026-05-21T09:00:00Z"))
        service.saveMatch(1L, UUID.fromString("00000000-0000-0000-0000-000000000002"), command(venue.id, playedAt = "2026-05-22T09:00:00Z"))
        service.saveMatch(1L, UUID.fromString("00000000-0000-0000-0000-000000000003"), command(venue.id, playedAt = "2026-05-23T09:00:00Z"))

        val firstPage = service.listMyMatches(1L, cursor = null, size = 2)
        val secondPage = service.listMyMatches(1L, cursor = firstPage.nextCursor, size = 2)

        assertEquals(listOf("2026-05-23T09:00:00Z", "2026-05-22T09:00:00Z"), firstPage.content.map { it.playedAt.toString() })
        assertNotNull(firstPage.nextCursor)
        assertEquals(true, firstPage.hasNext)
        assertEquals(listOf("2026-05-21T09:00:00Z"), secondPage.content.map { it.playedAt.toString() })
        assertNull(secondPage.nextCursor)
        assertEquals(false, secondPage.hasNext)
    }

    @Test
    fun `본인 경기를 삭제한다`() {
        val venue = saveVenue(userId = 1L)
        val match = service.saveMatch(1L, CLIENT_MATCH_ID, command(venue.id)).match

        service.deleteMyMatch(1L, match.id)

        val exception = assertFailsWith<KickLogException> {
            service.getMyMatch(1L, match.id)
        }
        assertEquals(ErrorCode.MATCH_NOT_FOUND, exception.errorCode)
    }

    @Test
    fun `다른 사용자의 경기 삭제는 거부한다`() {
        val venue = saveVenue(userId = 1L)
        val match = service.saveMatch(1L, CLIENT_MATCH_ID, command(venue.id)).match

        val exception = assertFailsWith<KickLogException> {
            service.deleteMyMatch(2L, match.id)
        }

        assertEquals(ErrorCode.MATCH_NOT_OWNED, exception.errorCode)
    }

    private fun saveVenue(userId: Long): Venue {
        return venueRepository.save(
            Venue.create(
                userId = userId,
                name = "풍경운동장-$userId",
                geoLat = BigDecimal("37.668100"),
                geoLng = BigDecimal("126.799200"),
                address = null,
                roadAddress = null,
                provider = "kakao",
                providerPlaceId = "place-$userId",
            ),
        )
    }

    private fun command(
        venueId: Long,
        playedAt: String = "2026-05-23T09:00:00Z",
        goals: Int = 1,
        workoutId: String = "hk-uuid-1",
    ): UpsertMatchCommand {
        return UpsertMatchCommand(
            venueId = venueId,
            playedAt = Instant.parse(playedAt),
            opponent = "OO FC",
            result = MatchResultType.WIN,
            position = MatchPosition.MF,
            goals = goals,
            assists = 0,
            quarters = listOf(
                UpsertQuarterCommand(
                    quarterNumber = 1,
                    healthKitWorkoutId = workoutId,
                    startedAt = Instant.parse(playedAt),
                    endedAt = Instant.parse("2026-05-23T09:15:00Z"),
                ),
            ),
        )
    }

    companion object {
        private val CLIENT_MATCH_ID: UUID = UUID.fromString("11111111-1111-1111-1111-111111111111")
    }
}
