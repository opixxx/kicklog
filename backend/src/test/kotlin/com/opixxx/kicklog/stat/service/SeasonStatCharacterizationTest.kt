package com.opixxx.kicklog.stat.service

import com.opixxx.kicklog.friend.repository.InMemoryFriendshipRepository
import com.opixxx.kicklog.friend.service.FriendshipAuthorizer
import com.opixxx.kicklog.match.repository.InMemoryMatchRepository
import com.opixxx.kicklog.match.service.MatchResultType
import com.opixxx.kicklog.testsupport.SeasonAggregateFixtures
import com.opixxx.kicklog.testsupport.SeasonAggregateFixtures.MatchSpec
import com.opixxx.kicklog.testsupport.SeasonAggregateFixtures.QuarterSpec
import com.opixxx.kicklog.user.repository.InMemoryUserRepository
import kotlin.test.Test
import kotlin.test.assertEquals

/**
 * EXEC_PLAN 2026-09-16 season-stat-sql-aggregation (3-B / B-2) — 참조 구현 특성화 테스트.
 *
 * `InMemoryMatchRepository` 는 리팩토링 후에도 **현재 Kotlin 집계 로직을 그대로 유지하는 참조 구현**이다.
 * 이 테스트는 그 참조 구현이 지켜야 할 계약(= 지금 사용자에게 보이는 숫자)을 못으로 박는다.
 * 기존 [SeasonStatServiceTest] 가 커버하지 못하는 네 가지 함정만 다룬다.
 *
 * - 경기당 쿼터 복수 (fan-out 중복 합산)
 * - durationSeconds 합 0 (0 division)
 * - 쿼터 없는 경기 (LEFT JOIN 누락 시 경기가 통째로 사라짐)
 * - UTC 월 경계 (api-spec §8.1)
 * - 가중평균 심박의 소수점 버림 (정수 나눗셈 계약)
 */
class SeasonStatCharacterizationTest {

    private val matchRepository = InMemoryMatchRepository()
    private val friendshipRepository = InMemoryFriendshipRepository()
    private val userRepository = InMemoryUserRepository()
    private val friendshipAuthorizer = FriendshipAuthorizer(friendshipRepository, userRepository)
    private val service = SeasonStatService(matchRepository, friendshipAuthorizer)

    private val userId = 1L
    private val venueId = 1L

    @Test
    fun `경기당 쿼터가 여러 개여도 거리와 골과 어시스트가 중복 합산되지 않는다`() {
        // 경기 2건 × 쿼터 3개 — 쿼터 기준으로 fan-out 되면 totalDistanceM 이 36000 이 된다.
        save(
            MatchSpec(
                playedAt = "2026-03-01T09:00:00Z", totalDistanceM = 5000, goals = 2, assists = 1,
                maxSpeedKmh = 29.4, sprintCount = 11,
                quarters = List(3) { QuarterSpec(durationSeconds = 900, avgHeartRate = 150) },
            ),
        )
        save(
            MatchSpec(
                playedAt = "2026-05-01T09:00:00Z", totalDistanceM = 7000, goals = 1, assists = 2,
                maxSpeedKmh = 26.0, sprintCount = 17,
                quarters = List(3) { QuarterSpec(durationSeconds = 900, avgHeartRate = 120) },
            ),
        )

        val stat = service.getMySeasonStat(userId, 2026)

        assertEquals(12000, stat.totalDistanceM)
        assertEquals(3, stat.totalGoals)
        assertEquals(3, stat.totalAssists)
        assertEquals(2, stat.matchCount)
        assertEquals(2, stat.winCount)
        // 쿼터 단위 지표는 6개가 맞다 — 경기 지표만 중복되면 안 된다.
        assertEquals(6, stat.quarterCount)
        // 가중평균 = (3*900*150 + 3*900*120) / 5400 = 135
        assertEquals(135, stat.avgHeartRate)
        assertEquals(7000, stat.best.longestMatchDistanceM)
        assertEquals(29.4, stat.best.maxSpeedKmh)
        assertEquals(17, stat.best.mostSprintCount)
        val expectedMonthly = MutableList(12) { 0 }
        expectedMonthly[2] = 5000   // 3월
        expectedMonthly[4] = 7000   // 5월
        assertEquals(expectedMonthly, stat.monthlyDistanceM)
    }

    @Test
    fun `쿼터 durationSeconds 합이 0 이면 avgHeartRate 는 0 이다`() {
        // 심박 값은 있지만 운동 시간이 0 — 가중평균의 분모가 0 이 된다.
        save(
            MatchSpec(
                playedAt = "2026-03-01T09:00:00Z", totalDistanceM = 5000,
                quarters = listOf(
                    QuarterSpec(durationSeconds = 0, avgHeartRate = 150),
                    QuarterSpec(durationSeconds = 0, avgHeartRate = 160),
                ),
            ),
        )

        val stat = service.getMySeasonStat(userId, 2026)

        assertEquals(0, stat.avgHeartRate)
        assertEquals(2, stat.quarterCount)
        assertEquals(5000, stat.totalDistanceM)
    }

    @Test
    fun `쿼터가 없는 경기도 경기 지표는 집계되고 quarterCount 는 0 이다`() {
        save(
            MatchSpec(
                playedAt = "2026-04-01T09:00:00Z", totalDistanceM = 6100, goals = 1, assists = 1,
                maxSpeedKmh = 21.5, sprintCount = 5, quarters = emptyList(),
            ),
        )

        val stat = service.getMySeasonStat(userId, 2026)

        assertEquals(1, stat.matchCount)
        assertEquals(6100, stat.totalDistanceM)
        assertEquals(1, stat.totalGoals)
        assertEquals(1, stat.totalAssists)
        assertEquals(0, stat.quarterCount)
        assertEquals(0, stat.avgHeartRate)
        assertEquals(21.5, stat.best.maxSpeedKmh)
    }

    @Test
    fun `UTC 12월 말 경기는 해당 연도 12월에 집계된다`() {
        // 2026-12-31T15:00Z 는 KST 로 2027-01-01 06:00 — 서버 TZ 를 타면 1월 또는 다음 시즌으로 샌다.
        save(MatchSpec(playedAt = "2026-12-31T15:00:00Z", totalDistanceM = 4000))
        save(MatchSpec(playedAt = "2026-12-31T23:00:00Z", totalDistanceM = 1000))
        // 시즌 밖 — 2026 통계에 들어오면 안 된다.
        save(MatchSpec(playedAt = "2027-01-01T00:00:00Z", totalDistanceM = 9999))

        val stat = service.getMySeasonStat(userId, 2026)

        assertEquals(2, stat.matchCount)
        assertEquals(5000, stat.totalDistanceM)
        assertEquals(5000, stat.monthlyDistanceM[11])   // 12월
        assertEquals(0, stat.monthlyDistanceM[0])       // 1월로 새지 않는다
    }

    @Test
    fun `가중평균 심박은 소수점을 버린다`() {
        // (300*151 + 300*150) / 600 = 150.5 → 150 (반올림 아님)
        save(
            MatchSpec(
                playedAt = "2026-06-01T09:00:00Z", totalDistanceM = 1000,
                quarters = listOf(
                    QuarterSpec(durationSeconds = 300, avgHeartRate = 151),
                    QuarterSpec(durationSeconds = 300, avgHeartRate = 150),
                ),
            ),
        )

        val stat = service.getMySeasonStat(userId, 2026)

        assertEquals(150, stat.avgHeartRate)
    }

    @Test
    fun `승무패는 경기 단위로만 센다`() {
        // 쿼터가 여러 개여도 winCount 가 쿼터 수만큼 부풀면 안 된다.
        save(
            MatchSpec(
                playedAt = "2026-03-01T09:00:00Z", result = MatchResultType.WIN,
                quarters = List(3) { QuarterSpec() },
            ),
        )
        save(
            MatchSpec(
                playedAt = "2026-03-08T09:00:00Z", result = MatchResultType.DRAW,
                quarters = List(4) { QuarterSpec() },
            ),
        )
        save(
            MatchSpec(
                playedAt = "2026-03-15T09:00:00Z", result = MatchResultType.LOSS,
                quarters = List(2) { QuarterSpec() },
            ),
        )

        val stat = service.getMySeasonStat(userId, 2026)

        assertEquals(1, stat.winCount)
        assertEquals(1, stat.drawCount)
        assertEquals(1, stat.lossCount)
        assertEquals(3, stat.matchCount)
        assertEquals(9, stat.quarterCount)
    }

    private fun save(spec: MatchSpec) {
        matchRepository.save(SeasonAggregateFixtures.match(userId, venueId, spec))
    }
}
