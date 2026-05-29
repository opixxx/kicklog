package com.opixxx.kicklog.match.service

import java.time.Instant

data class UpsertMatchCommand(
    val venueId: Long,
    val playedAt: Instant,
    val opponent: String?,
    val position: MatchPosition?,
    val goals: Int,
    val assists: Int,
    val quarters: List<UpsertQuarterCommand>,
    val opponentGoals: Int? = null,
    // 팀 전체 골. null = 미입력 — Match.replaceWith 가 result 도 null 로 derive.
    val teamGoals: Int? = null,
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
    // ADR-0001 D8 (2026-05-29 개정) — 쿼터별 최고속도. iOS distance 샘플 기반 derive + 35 km/h cap.
    val maxSpeedKmh: Double = 0.0,
    val avgHeartRate: Int = 0,
    val maxHeartRate: Int = 0,
    val sprintCount: Int = 0,
    val activeEnergyKcal: Int = 0,
)
