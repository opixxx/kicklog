package com.opixxx.kicklog.match.service

import java.time.Instant

data class UpsertMatchCommand(
    val venueId: Long,
    val playedAt: Instant,
    val opponent: String?,
    val result: MatchResultType?,
    val position: MatchPosition?,
    val goals: Int,
    val assists: Int,
    val quarters: List<UpsertQuarterCommand>,
)

data class UpsertQuarterCommand(
    val quarterNumber: Int,
    val healthKitWorkoutId: String,
    val startedAt: Instant,
    val endedAt: Instant,
)
