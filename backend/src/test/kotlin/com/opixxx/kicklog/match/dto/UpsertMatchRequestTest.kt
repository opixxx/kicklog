package com.opixxx.kicklog.match.dto

import jakarta.validation.Validation
import jakarta.validation.Validator
import java.time.Instant
import kotlin.test.AfterTest
import kotlin.test.BeforeTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

/**
 * UpsertMatchRequest 의 cross-field 검증.
 *
 * - teamGoals 는 nullable (미입력 가능)
 * - teamGoals 가 set 되면 0 이상이어야 함
 * - teamGoals 가 set 되고 goals 도 set 되면 teamGoals >= goals 강제
 *   (본인 골이 팀 전체 골보다 클 수 없음)
 */
class UpsertMatchRequestTest {

    private lateinit var validator: Validator

    @BeforeTest
    fun setUp() {
        validator = Validation.buildDefaultValidatorFactory().validator
    }

    @AfterTest
    fun tearDown() {
        // no-op
    }

    @Test
    fun `teamGoals null 은 통과한다 (모름 상태)`() {
        val request = request(goals = 2, teamGoals = null)

        val violations = validator.validate(request)

        assertEquals(0, teamGoalsViolations(violations).size)
    }

    @Test
    fun `teamGoals 가 goals 보다 작으면 검증 실패`() {
        val request = request(goals = 2, teamGoals = 1)

        val violations = validator.validate(request)

        val teamGoalsErrors = teamGoalsViolations(violations)
        assertEquals(1, teamGoalsErrors.size)
        assertTrue(
            teamGoalsErrors.any { it.message.contains("팀 전체 골") },
            "팀 전체 골 메시지 포함 — 실제: ${teamGoalsErrors.map { it.message }}",
        )
    }

    @Test
    fun `teamGoals 가 goals 와 같으면 통과한다`() {
        val request = request(goals = 2, teamGoals = 2)

        val violations = validator.validate(request)

        assertEquals(0, teamGoalsViolations(violations).size)
    }

    @Test
    fun `teamGoals 가 goals 보다 크면 통과한다`() {
        val request = request(goals = 1, teamGoals = 3)

        val violations = validator.validate(request)

        assertEquals(0, teamGoalsViolations(violations).size)
    }

    @Test
    fun `teamGoals 가 음수면 검증 실패`() {
        val request = request(goals = 0, teamGoals = -1)

        val violations = validator.validate(request)

        assertTrue(teamGoalsViolations(violations).isNotEmpty(), "teamGoals 음수 violation 누락")
    }

    private fun teamGoalsViolations(violations: Set<jakarta.validation.ConstraintViolation<UpsertMatchRequest>>) =
        violations.filter { violation ->
            val path = violation.propertyPath.toString()
            path.contains("teamGoals", ignoreCase = true) ||
                path.contains("TeamGoals", ignoreCase = false) ||
                // @AssertTrue getter 의 propertyPath 는 boolean property 이름이 됨
                path.contains("ValidTeamGoals", ignoreCase = false) ||
                path.contains("teamGoalsConsistent", ignoreCase = false) ||
                violation.message.contains("팀 전체 골") ||
                violation.message.contains("teamGoals", ignoreCase = true)
        }

    private fun request(
        goals: Int,
        teamGoals: Int?,
        opponentGoals: Int? = null,
    ): UpsertMatchRequest {
        return UpsertMatchRequest(
            venueId = 1L,
            playedAt = Instant.parse("2026-05-27T09:00:00Z"),
            opponent = "OO FC",
            position = null,
            goals = goals,
            assists = 0,
            opponentGoals = opponentGoals,
            teamGoals = teamGoals,
            totalDistanceM = 0,
            maxSpeedKmh = 0.0,
            sprintCount = 0,
            avgHeartRate = 0,
            quarters = listOf(
                UpsertQuarterRequest(
                    quarterNumber = 1,
                    healthKitWorkoutId = "hk-uuid-1",
                    startedAt = Instant.parse("2026-05-27T09:00:00Z"),
                    endedAt = Instant.parse("2026-05-27T09:15:00Z"),
                ),
            ),
        )
    }
}
