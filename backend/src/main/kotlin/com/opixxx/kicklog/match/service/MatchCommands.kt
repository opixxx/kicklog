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
    val totalDistanceM: Int = 0,
    val maxSpeedKmh: Double = 0.0,
    val sprintCount: Int = 0,
    val avgHeartRate: Int = 0,
)

data class UpsertQuarterCommand(
    val quarterNumber: Int,
    val healthKitWorkoutId: String,
    val startedAt: Instant,
    val endedAt: Instant,
    val durationSeconds: Int = 0,
    val distanceM: Int = 0,
    val avgSpeedKmh: Double = 0.0,
    val avgHeartRate: Int = 0,
    val maxHeartRate: Int = 0,
    val sprintCount: Int = 0,
    val activeEnergyKcal: Int = 0,
)
