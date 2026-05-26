package com.opixxx.kicklog.stat.service

import com.opixxx.kicklog.common.exception.ErrorCode
import com.opixxx.kicklog.common.exception.KickLogException
import com.opixxx.kicklog.friend.repository.InMemoryFriendshipRepository
import com.opixxx.kicklog.friend.service.FriendshipAuthorizer
import com.opixxx.kicklog.match.repository.InMemoryMatchRepository
import com.opixxx.kicklog.match.service.MatchPosition
import com.opixxx.kicklog.match.service.MatchResultType
import com.opixxx.kicklog.match.service.MatchService
import com.opixxx.kicklog.match.service.UpsertMatchCommand
import com.opixxx.kicklog.match.service.UpsertQuarterCommand
import com.opixxx.kicklog.testsupport.ServiceTestFixtures.matchCommand
import com.opixxx.kicklog.testsupport.ServiceTestFixtures.saveAcceptedFriendship
import com.opixxx.kicklog.testsupport.ServiceTestFixtures.saveUser
import com.opixxx.kicklog.testsupport.ServiceTestFixtures.saveVenue
import com.opixxx.kicklog.user.repository.InMemoryUserRepository
import com.opixxx.kicklog.venue.repository.InMemoryVenueRepository
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
        val venue = saveVenue(venueRepository, userId = 1L, namePrefix = "시즌운동장")
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
        // matchCommand default 가 WIN — 둘 다 WIN
        assertEquals(2, stat.winCount)
        assertEquals(0, stat.drawCount)
        assertEquals(0, stat.lossCount)
        // 모든 quarter avgHeartRate=145 (fixture default), duration 동일이라 가중평균도 145
        assertEquals(145, stat.avgHeartRate)
        // 1월(index 0) 7000m, 12월(index 11) 8200m, 나머지 0
        val expectedMonthly = MutableList(12) { 0 }
        expectedMonthly[0] = 7000
        expectedMonthly[11] = 8200
        assertEquals(expectedMonthly, stat.monthlyDistanceM)
    }

    @Test
    fun `경기 없는 연도는 0값을 반환한다`() {
        val stat = service.getMySeasonStat(1L, 2024)

        assertEquals(0, stat.totalDistanceM)
        assertEquals(0, stat.matchCount)
        assertEquals(0.0, stat.best.maxSpeedKmh)
        assertEquals(0, stat.winCount)
        assertEquals(0, stat.drawCount)
        assertEquals(0, stat.lossCount)
        assertEquals(0, stat.avgHeartRate)
        assertEquals(List(12) { 0 }, stat.monthlyDistanceM)
    }

    @Test
    fun `result 별 매치 수를 분류한다`() {
        val venue = saveVenue(venueRepository, userId = 1L, namePrefix = "분류운동장")
        saveMatchWithResult(1L, venue.id, "2026-03-01T09:00:00Z", MatchResultType.WIN)
        saveMatchWithResult(1L, venue.id, "2026-03-08T09:00:00Z", MatchResultType.WIN)
        saveMatchWithResult(1L, venue.id, "2026-04-01T09:00:00Z", MatchResultType.DRAW)
        saveMatchWithResult(1L, venue.id, "2026-05-01T09:00:00Z", MatchResultType.LOSS)

        val stat = service.getMySeasonStat(1L, 2026)

        assertEquals(2, stat.winCount)
        assertEquals(1, stat.drawCount)
        assertEquals(1, stat.lossCount)
        assertEquals(4, stat.matchCount)
    }

    @Test
    fun `평균 심박은 쿼터 시간 가중평균으로 계산한다`() {
        val venue = saveVenue(venueRepository, userId = 1L, namePrefix = "심박운동장")
        // 매치 1: 쿼터 1개 = 300초 × 150bpm
        // 매치 2: 쿼터 1개 = 600초 × 120bpm
        // 가중평균 = (300*150 + 600*120) / (300+600) = (45000+72000)/900 = 130
        saveMatchWithQuarters(
            1L, venue.id, "2026-03-01T09:00:00Z",
            listOf(quarter(quarterNumber = 1, startedAt = Instant.parse("2026-03-01T09:00:00Z"), durationSeconds = 300, avgHeartRate = 150)),
        )
        saveMatchWithQuarters(
            1L, venue.id, "2026-04-01T09:00:00Z",
            listOf(quarter(quarterNumber = 1, startedAt = Instant.parse("2026-04-01T09:00:00Z"), durationSeconds = 600, avgHeartRate = 120)),
        )

        val stat = service.getMySeasonStat(1L, 2026)

        assertEquals(130, stat.avgHeartRate)
    }

    @Test
    fun `월별 이동거리 집계는 12개월 배열을 반환한다`() {
        val venue = saveVenue(venueRepository, userId = 1L, namePrefix = "월별운동장")
        saveMatch(1L, venue.id, "2026-01-10T09:00:00Z", distance = 5000, goals = 0, assists = 0, sprint = 0)
        saveMatch(1L, venue.id, "2026-06-10T09:00:00Z", distance = 7000, goals = 0, assists = 0, sprint = 0)
        saveMatch(1L, venue.id, "2026-06-20T09:00:00Z", distance = 8000, goals = 0, assists = 0, sprint = 0)
        saveMatch(1L, venue.id, "2026-12-31T09:00:00Z", distance = 4000, goals = 0, assists = 0, sprint = 0)

        val stat = service.getMySeasonStat(1L, 2026)

        val expected = MutableList(12) { 0 }
        expected[0] = 5000        // 1월
        expected[5] = 15000       // 6월 합산
        expected[11] = 4000       // 12월
        assertEquals(expected, stat.monthlyDistanceM)
        assertEquals(12, stat.monthlyDistanceM.size)
    }

    @Test
    fun `accepted 친구 통계를 조회한다`() {
        val viewer = saveUser(userRepository, "조회자")
        val friend = saveUser(userRepository, "친구")
        val venue = saveVenue(venueRepository, userId = friend.id, namePrefix = "시즌운동장")
        saveAcceptedFriendship(friendshipRepository, viewer.id, friend.id)
        saveMatch(friend.id, venue.id, "2026-06-10T09:00:00Z", distance = 5000, goals = 1, assists = 0, sprint = 7)

        val stat = service.getFriendSeasonStat(viewer.id, friend.id, 2026)

        assertEquals(5000, stat.totalDistanceM)
        assertEquals(1, stat.matchCount)
    }

    @Test
    fun `친구가 아니면 통계 조회를 거부한다`() {
        val viewer = saveUser(userRepository, "조회자")
        val other = saveUser(userRepository, "비친구")

        val exception = assertFailsWith<KickLogException> {
            service.getFriendSeasonStat(viewer.id, other.id, 2026)
        }

        assertEquals(ErrorCode.FRIEND_UNAUTHORIZED, exception.errorCode)
    }

    // MARK: - 헬퍼

    private fun saveMatch(userId: Long, venueId: Long, playedAt: String, distance: Int, goals: Int, assists: Int, sprint: Int) {
        matchService.saveMatch(
            userId,
            UUID.randomUUID(),
            matchCommand(
                venueId = venueId,
                playedAt = playedAt,
                goals = goals,
                assists = assists,
                distanceM = distance,
                maxSpeedKmh = 28.5,
                sprintCount = sprint,
                avgHeartRate = 150,
            ),
        )
    }

    private fun saveMatchWithResult(userId: Long, venueId: Long, playedAt: String, result: MatchResultType) {
        val instant = Instant.parse(playedAt)
        // result 는 백엔드에서 teamGoals vs opponentGoals 로 derive — 외부 result 인자에 매핑되는 점수 쌍을 만들어준다.
        val (teamGoals, opponentGoals) = when (result) {
            MatchResultType.WIN -> 1 to 0
            MatchResultType.DRAW -> 0 to 0
            MatchResultType.LOSS -> 0 to 1
        }
        matchService.saveMatch(
            userId,
            UUID.randomUUID(),
            UpsertMatchCommand(
                venueId = venueId,
                playedAt = instant,
                opponent = "TestFC",
                position = MatchPosition.MF,
                goals = 0,
                assists = 0,
                opponentGoals = opponentGoals,
                teamGoals = teamGoals,
                totalDistanceM = 1000,
                maxSpeedKmh = 0.0,
                sprintCount = 0,
                avgHeartRate = 0,
                quarters = listOf(quarter(quarterNumber = 1, startedAt = instant, durationSeconds = 900, avgHeartRate = 145)),
            ),
        )
    }

    private fun saveMatchWithQuarters(userId: Long, venueId: Long, playedAt: String, quarters: List<UpsertQuarterCommand>) {
        val instant = Instant.parse(playedAt)
        matchService.saveMatch(
            userId,
            UUID.randomUUID(),
            UpsertMatchCommand(
                venueId = venueId,
                playedAt = instant,
                opponent = "TestFC",
                position = MatchPosition.MF,
                goals = 0,
                assists = 0,
                opponentGoals = 0,
                teamGoals = 1,
                totalDistanceM = quarters.sumOf { it.distanceM },
                maxSpeedKmh = 0.0,
                sprintCount = 0,
                avgHeartRate = 0,
                quarters = quarters,
            ),
        )
    }

    private fun quarter(
        quarterNumber: Int,
        startedAt: Instant,
        durationSeconds: Int,
        avgHeartRate: Int,
        distanceM: Int = 0,
    ): UpsertQuarterCommand {
        return UpsertQuarterCommand(
            quarterNumber = quarterNumber,
            healthKitWorkoutId = "hk-$quarterNumber-${startedAt.epochSecond}",
            startedAt = startedAt,
            endedAt = startedAt.plusSeconds(durationSeconds.toLong()),
            durationSeconds = durationSeconds,
            distanceM = distanceM,
            avgSpeedKmh = 0.0,
            avgHeartRate = avgHeartRate,
            maxHeartRate = avgHeartRate + 10,
            sprintCount = 0,
            activeEnergyKcal = 0,
        )
    }
}
