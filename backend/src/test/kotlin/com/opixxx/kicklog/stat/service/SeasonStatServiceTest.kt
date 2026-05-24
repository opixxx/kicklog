package com.opixxx.kicklog.stat.service

import com.opixxx.kicklog.common.exception.ErrorCode
import com.opixxx.kicklog.common.exception.KickLogException
import com.opixxx.kicklog.friend.entity.Friendship
import com.opixxx.kicklog.friend.repository.InMemoryFriendshipRepository
import com.opixxx.kicklog.friend.service.FriendshipAuthorizer
import com.opixxx.kicklog.match.repository.InMemoryMatchRepository
import com.opixxx.kicklog.match.service.MatchPosition
import com.opixxx.kicklog.match.service.MatchResultType
import com.opixxx.kicklog.match.service.MatchService
import com.opixxx.kicklog.match.service.UpsertMatchCommand
import com.opixxx.kicklog.match.service.UpsertQuarterCommand
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

class SeasonStatServiceTest {

    private val matchRepository = InMemoryMatchRepository()
    private val venueRepository = InMemoryVenueRepository()
    private val friendshipRepository = InMemoryFriendshipRepository()
    private val userRepository = InMemoryUserRepository()
    private val friendshipAuthorizer = FriendshipAuthorizer(friendshipRepository, userRepository)
    private val matchService = MatchService(matchRepository, venueRepository, friendshipAuthorizer)
    private val service = SeasonStatService(matchRepository, friendshipAuthorizer)

    @Test
    fun `같은 연도 경기만 시즌 통계로 집계한다`() {
        val venue = saveVenue(userId = 1L)
        saveMatch(1L, venue.id, "2026-01-10T09:00:00Z", distance = 7000, goals = 2, assists = 1, sprint = 12)
        saveMatch(1L, venue.id, "2026-12-20T09:00:00Z", distance = 8200, goals = 1, assists = 2, sprint = 15)
        saveMatch(1L, venue.id, "2025-12-20T09:00:00Z", distance = 9900, goals = 9, assists = 9, sprint = 30)

        val stat = service.getMySeasonStat(1L, 2026)

        assertEquals(2026, stat.year)
        assertEquals(15200, stat.totalDistanceM)
        assertEquals(3, stat.totalGoals)
        assertEquals(3, stat.totalAssists)
        assertEquals(2, stat.matchCount)
        assertEquals(2, stat.quarterCount)
        assertEquals(28.5, stat.best.maxSpeedKmh)
        assertEquals(8200, stat.best.longestMatchDistanceM)
        assertEquals(15, stat.best.mostSprintCount)
    }

    @Test
    fun `경기 없는 연도는 0값을 반환한다`() {
        val stat = service.getMySeasonStat(1L, 2024)

        assertEquals(0, stat.totalDistanceM)
        assertEquals(0, stat.matchCount)
        assertEquals(0.0, stat.best.maxSpeedKmh)
    }

    @Test
    fun `accepted 친구 통계를 조회한다`() {
        val viewer = saveUser("조회자")
        val friend = saveUser("친구")
        val venue = saveVenue(userId = friend.id)
        saveAcceptedFriendship(viewer.id, friend.id)
        saveMatch(friend.id, venue.id, "2026-06-10T09:00:00Z", distance = 5000, goals = 1, assists = 0, sprint = 7)

        val stat = service.getFriendSeasonStat(viewer.id, friend.id, 2026)

        assertEquals(5000, stat.totalDistanceM)
        assertEquals(1, stat.matchCount)
    }

    @Test
    fun `친구가 아니면 통계 조회를 거부한다`() {
        val viewer = saveUser("조회자")
        val other = saveUser("비친구")

        val exception = assertFailsWith<KickLogException> {
            service.getFriendSeasonStat(viewer.id, other.id, 2026)
        }

        assertEquals(ErrorCode.FRIEND_UNAUTHORIZED, exception.errorCode)
    }

    private fun saveMatch(userId: Long, venueId: Long, playedAt: String, distance: Int, goals: Int, assists: Int, sprint: Int) {
        matchService.saveMatch(
            userId,
            UUID.randomUUID(),
            command(venueId, playedAt, distance, goals, assists, sprint),
        )
    }

    private fun command(venueId: Long, playedAt: String, distance: Int, goals: Int, assists: Int, sprint: Int): UpsertMatchCommand {
        return UpsertMatchCommand(
            venueId = venueId,
            playedAt = Instant.parse(playedAt),
            opponent = "OO FC",
            result = MatchResultType.WIN,
            position = MatchPosition.MF,
            goals = goals,
            assists = assists,
            totalDistanceM = distance,
            maxSpeedKmh = 28.5,
            sprintCount = sprint,
            avgHeartRate = 150,
            quarters = listOf(
                UpsertQuarterCommand(
                    quarterNumber = 1,
                    healthKitWorkoutId = "hk-$playedAt",
                    startedAt = Instant.parse(playedAt),
                    endedAt = Instant.parse(playedAt).plusSeconds(900),
                    durationSeconds = 900,
                    distanceM = distance,
                    avgSpeedKmh = 6.1,
                    avgHeartRate = 145,
                    maxHeartRate = 160,
                    sprintCount = sprint,
                    activeEnergyKcal = 120,
                ),
            ),
        )
    }

    private fun saveVenue(userId: Long): Venue {
        return venueRepository.save(
            Venue.create(
                userId = userId,
                name = "시즌운동장-$userId",
                geoLat = BigDecimal("37.668100"),
                geoLng = BigDecimal("126.799200"),
                address = null,
                roadAddress = null,
                provider = "kakao",
                providerPlaceId = "season-place-$userId",
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
}
