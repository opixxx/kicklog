package com.opixxx.kicklog.match.dto

import com.opixxx.kicklog.match.entity.Match
import com.opixxx.kicklog.match.entity.QuarterWorkout
import com.opixxx.kicklog.match.service.MatchPosition
import com.opixxx.kicklog.match.service.MatchResultType
import java.time.Instant
import java.util.UUID
import kotlin.reflect.full.companionObject
import kotlin.reflect.full.declaredFunctions
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertTrue

/**
 * EXEC_PLAN 2026-05-28 p0-cleanup — `hideHeartRate` 정책 폐기.
 *
 * Match*Response.from(...) 시그니처가 단일 인자(match/quarter) 만 받게 축소되었고,
 * avgHeartRate / maxHeartRate 는 마스킹 없이 entity 값 그대로 노출된다.
 *
 * RED 단계: 현재 `from(match, hideHeartRate)` 시그니처라 호출부 컴파일 에러가 정상.
 */
class MatchDtosTest {

    private val playedAt: Instant = Instant.parse("2026-05-27T09:00:00Z")
    private val startedAt: Instant = playedAt
    private val endedAt: Instant = Instant.parse("2026-05-27T09:15:00Z")

    @Test
    fun `MatchDetailResponse from 은 단일 인자만 받고 avgHeartRate 를 평문 노출한다`() {
        val match = sampleMatch(avgHeartRate = 150)

        val response = MatchDetailResponse.from(match)

        assertEquals(150, response.avgHeartRate)
        assertEquals(match.clientMatchId, response.clientMatchId)
        // quarter 도 마스킹 없이 평문
        val quarter = response.quarters.single()
        assertEquals(148, quarter.avgHeartRate)
        assertEquals(160, quarter.maxHeartRate)
    }

    @Test
    fun `MatchSummaryResponse from 은 단일 인자만 받고 avgHeartRate 를 평문 노출한다`() {
        val match = sampleMatch(avgHeartRate = 152)

        val response = MatchSummaryResponse.from(match)

        assertEquals(152, response.avgHeartRate)
        assertEquals(1, response.quarterCount)
        assertEquals(MatchResultType.WIN, response.result)
    }

    @Test
    fun `QuarterWorkoutResponse from 은 단일 인자만 받고 avgHeartRate maxHeartRate 평문 노출`() {
        val match = sampleMatch(avgHeartRate = 145)
        val quarter = match.quarters.single()

        val response = QuarterWorkoutResponse.from(quarter)

        assertNotNull(response.avgHeartRate)
        assertEquals(148, response.avgHeartRate)
        assertEquals(160, response.maxHeartRate)
    }

    @Test
    fun `Match Response from 들의 파라미터에 hideHeartRate 가 더 이상 없어야 한다`() {
        // 정책 폐기 — from(...) 시그니처에서 hideHeartRate 자체가 제거되어야 한다.
        val matchDetailFrom = MatchDetailResponse::class.companionObject!!.declaredFunctions
            .single { it.name == "from" }
        val matchSummaryFrom = MatchSummaryResponse::class.companionObject!!.declaredFunctions
            .single { it.name == "from" }
        val quarterFrom = QuarterWorkoutResponse::class.companionObject!!.declaredFunctions
            .single { it.name == "from" }

        val allParamNames = listOf(matchDetailFrom, matchSummaryFrom, quarterFrom)
            .flatMap { it.parameters }
            .mapNotNull { it.name }

        assertTrue(
            allParamNames.none { it == "hideHeartRate" },
            "from(...) 시그니처에 hideHeartRate 파라미터가 남아있음: $allParamNames",
        )
    }

    private fun sampleMatch(avgHeartRate: Int): Match {
        val match = Match(
            id = 1L,
            userId = 100L,
            clientMatchId = UUID.fromString("11111111-1111-1111-1111-111111111111"),
            venueId = 9L,
            playedAt = playedAt,
            opponent = "OO FC",
            result = MatchResultType.WIN,
            position = MatchPosition.MF,
            goals = 1,
            assists = 0,
            opponentGoals = 0,
            teamGoals = 1,
            totalDistanceM = 5000,
            maxSpeedKmh = 24.0,
            sprintCount = 10,
            avgHeartRate = avgHeartRate,
        )
        // OneToMany 컬렉션에 직접 접근하지 않고 reflection 으로 quarter 1개 부착.
        val field = Match::class.java.getDeclaredField("quarterWorkouts")
        field.isAccessible = true
        @Suppress("UNCHECKED_CAST")
        val list = field.get(match) as MutableList<QuarterWorkout>
        list.add(
            QuarterWorkout(
                match = match,
                quarterNumber = 1,
                healthKitWorkoutId = "hk-uuid-1",
                startedAt = startedAt,
                endedAt = endedAt,
                durationSeconds = 900,
                distanceM = 2500,
                avgSpeedKmh = 9.5,
                avgHeartRate = 148,
                maxHeartRate = 160,
                sprintCount = 5,
                activeEnergyKcal = 200,
            ),
        )
        return match
    }
}
