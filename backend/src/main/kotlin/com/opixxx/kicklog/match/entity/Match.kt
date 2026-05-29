package com.opixxx.kicklog.match.entity

import com.opixxx.kicklog.common.exception.ErrorCode
import com.opixxx.kicklog.common.exception.KickLogException
import com.opixxx.kicklog.match.service.MatchPosition
import com.opixxx.kicklog.match.service.MatchResultType
import com.opixxx.kicklog.match.service.UpsertMatchCommand
import jakarta.persistence.CascadeType
import jakarta.persistence.Column
import jakarta.persistence.Entity
import jakarta.persistence.EnumType
import jakarta.persistence.Enumerated
import jakarta.persistence.FetchType
import jakarta.persistence.GeneratedValue
import jakarta.persistence.GenerationType
import jakarta.persistence.Id
import jakarta.persistence.OneToMany
import jakarta.persistence.Table
import java.time.Instant
import java.util.UUID

/**
 * 매치 Aggregate Root.
 *
 * **Invariant**: `result == MatchResultType.derive(teamGoals, opponentGoals)`.
 * - 결과는 (teamGoals, opponentGoals) 에서 derive 된 종속 필드다.
 * - 외부에서 `result` 를 직접 set 하지 말 것 — JPA reflection 을 제외하면 `replaceWith` 가 유일한 갱신 경로.
 * - 둘 중 하나라도 NULL 이면 result 도 NULL — "점수 모름" 상태에서 라벨링을 재저장하면 기존 W/D/L 결과는 의도적으로 리셋된다 (ADR-0003 D3).
 */
@Entity
@Table(name = "matches")
class Match(
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    var id: Long = 0,

    @Column(name = "user_id", nullable = false)
    var userId: Long,

    @Column(name = "client_match_id", nullable = false)
    var clientMatchId: UUID,

    @Column(name = "venue_id")
    var venueId: Long?,

    @Column(name = "played_at", nullable = false)
    var playedAt: Instant,

    @Column(name = "opponent", length = 100)
    var opponent: String?,

    @Enumerated(EnumType.STRING)
    @Column(name = "result", length = 10)
    var result: MatchResultType?,

    @Enumerated(EnumType.STRING)
    @Column(name = "position", length = 10)
    var position: MatchPosition?,

    @Column(name = "goals", nullable = false)
    var goals: Int,

    @Column(name = "assists", nullable = false)
    var assists: Int,

    // 상대팀 득점. null = 사용자가 점수 미입력. 0 = 명시적 무실점 (0:0 등).
    @Column(name = "opponent_goals")
    var opponentGoals: Int?,

    // 팀 전체 득점. null = 사용자가 미입력. result 는 teamGoals vs opponentGoals 로 자동 derive.
    @Column(name = "team_goals")
    var teamGoals: Int? = null,

    @Column(name = "total_distance_m", nullable = false)
    var totalDistanceM: Int = 0,

    @Column(name = "max_speed_kmh", nullable = false)
    var maxSpeedKmh: Double = 0.0,

    @Column(name = "sprint_count", nullable = false)
    var sprintCount: Int = 0,

    @Column(name = "avg_heart_rate", nullable = false)
    var avgHeartRate: Int = 0,

    @Column(name = "created_at", nullable = false)
    var createdAt: Instant = Instant.now(),

    @Column(name = "updated_at", nullable = false)
    var updatedAt: Instant = Instant.now(),

    @OneToMany(mappedBy = "match", cascade = [CascadeType.ALL], orphanRemoval = true, fetch = FetchType.LAZY)
    private val quarterWorkouts: MutableList<QuarterWorkout> = mutableListOf(),
) {
    val quarters: List<QuarterWorkout>
        get() = quarterWorkouts.sortedBy { it.quarterNumber }

    fun replaceWith(command: UpsertMatchCommand) {
        validateQuarters(command)
        venueId = command.venueId
        playedAt = command.playedAt
        opponent = command.opponent?.trim()?.takeIf { it.isNotBlank() }
        position = command.position
        goals = command.goals
        assists = command.assists
        opponentGoals = command.opponentGoals
        teamGoals = command.teamGoals
        recomputeResult()
        totalDistanceM = command.totalDistanceM
        maxSpeedKmh = command.maxSpeedKmh
        sprintCount = command.sprintCount
        avgHeartRate = command.avgHeartRate
        updatedAt = Instant.now()
        replaceQuarters(command)
    }

    // result 는 (teamGoals, opponentGoals) 의 derived field — 둘 중 하나라도 null 이면 null.
    // 호출은 replaceWith 안에서만 — 외부에서 result 를 직접 set 하지 않게 invariant 응집.
    private fun recomputeResult() {
        result = MatchResultType.derive(teamGoals, opponentGoals)
    }

    private fun validateQuarters(command: UpsertMatchCommand) {
        if (command.quarters.size > MAX_QUARTER_COUNT) {
            throw KickLogException(ErrorCode.MATCH_QUARTER_OVERFLOW)
        }
        if (command.quarters.map { it.quarterNumber }.distinct().size != command.quarters.size) {
            throw KickLogException(ErrorCode.MATCH_DUPLICATE_QUARTER_NO)
        }
    }

    private fun replaceQuarters(command: UpsertMatchCommand) {
        quarterWorkouts.clear()
        command.quarters.sortedBy { it.quarterNumber }.forEach {
            quarterWorkouts.add(
                QuarterWorkout(
                    match = this,
                    quarterNumber = it.quarterNumber,
                    healthKitWorkoutId = it.healthKitWorkoutId,
                    startedAt = it.startedAt,
                    endedAt = it.endedAt,
                    durationSeconds = it.durationSeconds,
                    distanceM = it.distanceM,
                    avgSpeedKmh = it.avgSpeedKmh,
                    maxSpeedKmh = it.maxSpeedKmh,
                    avgHeartRate = it.avgHeartRate,
                    maxHeartRate = it.maxHeartRate,
                    sprintCount = it.sprintCount,
                    activeEnergyKcal = it.activeEnergyKcal,
                ),
            )
        }
    }

    companion object {
        private const val MAX_QUARTER_COUNT = 4

        fun create(userId: Long, clientMatchId: UUID, command: UpsertMatchCommand): Match {
            return Match(
                userId = userId,
                clientMatchId = clientMatchId,
                venueId = command.venueId,
                playedAt = command.playedAt,
                opponent = null,
                result = null,
                position = null,
                goals = 0,
                assists = 0,
                opponentGoals = null,
            ).also { it.replaceWith(command) }
        }
    }
}
