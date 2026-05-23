package com.opixxx.kicklog.match.dto

import com.opixxx.kicklog.match.entity.Match
import com.opixxx.kicklog.match.entity.QuarterWorkout
import com.opixxx.kicklog.match.service.MatchPosition
import com.opixxx.kicklog.match.service.MatchResultType
import com.opixxx.kicklog.match.service.UpsertMatchCommand
import com.opixxx.kicklog.match.service.UpsertQuarterCommand
import jakarta.validation.Valid
import jakarta.validation.constraints.Max
import jakarta.validation.constraints.Min
import jakarta.validation.constraints.NotBlank
import jakarta.validation.constraints.NotEmpty
import jakarta.validation.constraints.NotNull
import jakarta.validation.constraints.Size
import java.time.Instant
import java.util.UUID

data class UpsertMatchRequest(
    @field:NotNull(message = "운동장 id를 입력해주세요")
    val venueId: Long,

    @field:NotNull(message = "경기 시간을 입력해주세요")
    val playedAt: Instant,

    @field:Size(max = 100, message = "상대 팀 이름은 100자 이하로 입력해주세요")
    val opponent: String? = null,

    val result: MatchResultType? = null,

    val position: MatchPosition? = null,

    @field:Min(value = 0, message = "득점은 0 이상이어야 합니다")
    val goals: Int = 0,

    @field:Min(value = 0, message = "도움은 0 이상이어야 합니다")
    val assists: Int = 0,

    @field:Valid
    @field:NotEmpty(message = "쿼터 정보를 1개 이상 입력해주세요")
    @field:Size(max = 4, message = "쿼터는 최대 4개까지 입력할 수 있습니다")
    val quarters: List<UpsertQuarterRequest>,
) {
    fun toCommand(): UpsertMatchCommand {
        return UpsertMatchCommand(
            venueId = venueId,
            playedAt = playedAt,
            opponent = opponent,
            result = result,
            position = position,
            goals = goals,
            assists = assists,
            quarters = quarters.map { it.toCommand() },
        )
    }
}

data class UpsertQuarterRequest(
    @field:Min(value = 1, message = "쿼터 번호는 1 이상이어야 합니다")
    @field:Max(value = 4, message = "쿼터 번호는 4 이하이어야 합니다")
    val quarterNumber: Int,

    @field:NotBlank(message = "HealthKit workout id를 입력해주세요")
    val healthKitWorkoutId: String,

    @field:NotNull(message = "쿼터 시작 시간을 입력해주세요")
    val startedAt: Instant,

    @field:NotNull(message = "쿼터 종료 시간을 입력해주세요")
    val endedAt: Instant,
) {
    fun toCommand(): UpsertQuarterCommand {
        return UpsertQuarterCommand(
            quarterNumber = quarterNumber,
            healthKitWorkoutId = healthKitWorkoutId,
            startedAt = startedAt,
            endedAt = endedAt,
        )
    }
}

data class MatchDetailResponse(
    val id: Long,
    val clientMatchId: UUID,
    val venueId: Long,
    val playedAt: Instant,
    val opponent: String?,
    val result: MatchResultType?,
    val position: MatchPosition?,
    val goals: Int,
    val assists: Int,
    val quarters: List<QuarterWorkoutResponse>,
) {
    companion object {
        fun from(match: Match): MatchDetailResponse {
            return MatchDetailResponse(
                id = match.id,
                clientMatchId = match.clientMatchId,
                venueId = match.venueId,
                playedAt = match.playedAt,
                opponent = match.opponent,
                result = match.result,
                position = match.position,
                goals = match.goals,
                assists = match.assists,
                quarters = match.quarters.map(QuarterWorkoutResponse::from),
            )
        }
    }
}

data class MatchSummaryResponse(
    val id: Long,
    val clientMatchId: UUID,
    val venueId: Long,
    val playedAt: Instant,
    val opponent: String?,
    val result: MatchResultType?,
    val position: MatchPosition?,
    val goals: Int,
    val assists: Int,
    val quarterCount: Int,
) {
    companion object {
        fun from(match: Match): MatchSummaryResponse {
            return MatchSummaryResponse(
                id = match.id,
                clientMatchId = match.clientMatchId,
                venueId = match.venueId,
                playedAt = match.playedAt,
                opponent = match.opponent,
                result = match.result,
                position = match.position,
                goals = match.goals,
                assists = match.assists,
                quarterCount = match.quarters.size,
            )
        }
    }
}

data class QuarterWorkoutResponse(
    val quarterNumber: Int,
    val healthKitWorkoutId: String,
    val startedAt: Instant,
    val endedAt: Instant,
) {
    companion object {
        fun from(quarter: QuarterWorkout): QuarterWorkoutResponse {
            return QuarterWorkoutResponse(
                quarterNumber = quarter.quarterNumber,
                healthKitWorkoutId = quarter.healthKitWorkoutId,
                startedAt = quarter.startedAt,
                endedAt = quarter.endedAt,
            )
        }
    }
}
