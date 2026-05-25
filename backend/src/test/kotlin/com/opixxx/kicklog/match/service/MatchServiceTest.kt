package com.opixxx.kicklog.match.service

import com.opixxx.kicklog.common.exception.ErrorCode
import com.opixxx.kicklog.common.exception.KickLogException
import com.opixxx.kicklog.friend.entity.Friendship
import com.opixxx.kicklog.friend.repository.InMemoryFriendshipRepository
import com.opixxx.kicklog.friend.service.FriendshipAuthorizer
import com.opixxx.kicklog.match.repository.InMemoryMatchRepository
import com.opixxx.kicklog.user.entity.User
import com.opixxx.kicklog.user.repository.InMemoryUserRepository
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
    private val friendshipRepository = InMemoryFriendshipRepository()
    private val userRepository = InMemoryUserRepository()
    private val friendshipAuthorizer = FriendshipAuthorizer(friendshipRepository, userRepository)
    private val service = MatchService(matchRepository, venueRepository, friendshipAuthorizer)

    @Test
    fun `경기를 신규 저장한다`() {
        val venue = saveVenue(userId = 1L)
        val result = service.saveMatch(1L, CLIENT_MATCH_ID, command(venue.id))

        assertEquals(false, result.updated)
        assertEquals(CLIENT_MATCH_ID, result.match.clientMatchId)
        assertEquals(1, result.match.quarters.size)
    }

    @Test
    fun `경기와 쿼터 metric을 저장한다`() {
        val venue = saveVenue(userId = 1L)

        val result = service.saveMatch(1L, CLIENT_MATCH_ID, metricCommand(venue.id))

        assertEquals(7200, result.match.totalDistanceM)
        assertEquals(28.4, result.match.maxSpeedKmh)
        assertEquals(17, result.match.sprintCount)
        assertEquals(151, result.match.avgHeartRate)
        assertEquals(3600, result.match.quarters.single().durationSeconds)
        assertEquals(4100, result.match.quarters.single().distanceM)
        assertEquals(156, result.match.quarters.single().maxHeartRate)
    }

    @Test
    fun `opponentGoals 를 저장하고 읽을 수 있다`() {
        val venue = saveVenue(userId = 1L)
        val cmd = command(venue.id, goals = 4).copy(opponentGoals = 2)

        val result = service.saveMatch(1L, CLIENT_MATCH_ID, cmd)

        assertEquals(4, result.match.goals)
        assertEquals(2, result.match.opponentGoals)
    }

    @Test
    fun `opponentGoals 미입력 시 null 로 저장된다`() {
        val venue = saveVenue(userId = 1L)

        val result = service.saveMatch(1L, CLIENT_MATCH_ID, command(venue.id))

        assertEquals(null, result.match.opponentGoals)
    }

    @Test
    fun `opponentGoals 가 0 이면 명시적 무실점으로 저장된다`() {
        val venue = saveVenue(userId = 1L)
        val cmd = command(venue.id).copy(opponentGoals = 0)

        val result = service.saveMatch(1L, CLIENT_MATCH_ID, cmd)

        assertEquals(0, result.match.opponentGoals)
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

    @Test
    fun `친구 경기 목록은 대상 사용자 경기만 반환한다`() {
        val viewer = saveUser("조회자")
        val friend = saveUser("친구")
        val friendVenue = saveVenue(friend.id)
        saveAcceptedFriendship(viewer.id, friend.id)
        service.saveMatch(friend.id, UUID.fromString("00000000-0000-0000-0000-000000000011"), command(friendVenue.id))

        val page = service.listFriendMatches(viewer.id, friend.id, cursor = null, size = 20)

        assertEquals(listOf(friend.id), page.page.content.map { it.userId })
    }

    @Test
    fun `친구 경기 상세는 대상 사용자 경기만 반환한다`() {
        val viewer = saveUser("조회자")
        val friend = saveUser("친구")
        val outsider = saveUser("다른사용자")
        val friendVenue = saveVenue(friend.id)
        val outsiderVenue = saveVenue(outsider.id)
        saveAcceptedFriendship(viewer.id, friend.id)
        service.saveMatch(friend.id, UUID.fromString("00000000-0000-0000-0000-000000000021"), command(friendVenue.id))
        val outsiderMatch = service.saveMatch(
            outsider.id,
            UUID.fromString("00000000-0000-0000-0000-000000000022"),
            command(outsiderVenue.id),
        ).match

        val exception = assertFailsWith<KickLogException> {
            service.getFriendMatch(viewer.id, friend.id, outsiderMatch.id)
        }

        assertEquals(ErrorCode.MATCH_NOT_FOUND, exception.errorCode)
    }

    @Test
    fun `친구가 아니면 친구 경기 목록을 조회할 수 없다`() {
        val viewer = saveUser("조회자")
        val other = saveUser("비친구")

        val exception = assertFailsWith<KickLogException> {
            service.listFriendMatches(viewer.id, other.id, cursor = null, size = 20)
        }

        assertEquals(ErrorCode.FRIEND_UNAUTHORIZED, exception.errorCode)
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

    private fun saveUser(displayName: String): User {
        return userRepository.save(User.create(displayName = displayName, email = "$displayName@example.com"))
    }

    private fun saveAcceptedFriendship(userId: Long, targetUserId: Long) {
        val now = Instant.parse("2026-05-23T09:00:00Z")
        val friendship = Friendship.createPending(userId, targetUserId, now)
        friendship.accept(now)
        friendshipRepository.save(friendship)
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

    private fun metricCommand(venueId: Long): UpsertMatchCommand {
        return command(venueId).copy(
            totalDistanceM = 7200,
            maxSpeedKmh = 28.4,
            sprintCount = 17,
            avgHeartRate = 151,
            quarters = listOf(
                command(venueId).quarters.single().copy(
                    durationSeconds = 3600,
                    distanceM = 4100,
                    avgSpeedKmh = 6.9,
                    avgHeartRate = 148,
                    maxHeartRate = 156,
                    sprintCount = 9,
                    activeEnergyKcal = 430,
                ),
            ),
        )
    }

    companion object {
        private val CLIENT_MATCH_ID: UUID = UUID.fromString("11111111-1111-1111-1111-111111111111")
    }
}
