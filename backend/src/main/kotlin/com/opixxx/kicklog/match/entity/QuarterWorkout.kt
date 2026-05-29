package com.opixxx.kicklog.match.entity

import jakarta.persistence.Column
import jakarta.persistence.Entity
import jakarta.persistence.FetchType
import jakarta.persistence.GeneratedValue
import jakarta.persistence.GenerationType
import jakarta.persistence.Id
import jakarta.persistence.JoinColumn
import jakarta.persistence.ManyToOne
import jakarta.persistence.Table
import java.time.Instant

@Entity
@Table(name = "quarter_workouts")
class QuarterWorkout(
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    var id: Long = 0,

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "match_id", nullable = false)
    var match: Match,

    @Column(name = "quarter_number", nullable = false)
    var quarterNumber: Int,

    @Column(name = "health_kit_workout_id", nullable = false)
    var healthKitWorkoutId: String,

    @Column(name = "started_at", nullable = false)
    var startedAt: Instant,

    @Column(name = "ended_at", nullable = false)
    var endedAt: Instant,

    @Column(name = "duration_seconds", nullable = false)
    var durationSeconds: Int = 0,

    @Column(name = "distance_m", nullable = false)
    var distanceM: Int = 0,

    @Column(name = "avg_speed_kmh", nullable = false)
    var avgSpeedKmh: Double = 0.0,

    // ADR-0001 D8 (2026-05-29 개정) — 쿼터별 최고속도. iOS 가 distance 샘플 기반 derive + 35 km/h cap 적용한 값.
    @Column(name = "max_speed_kmh", nullable = false)
    var maxSpeedKmh: Double = 0.0,

    @Column(name = "avg_heart_rate", nullable = false)
    var avgHeartRate: Int = 0,

    @Column(name = "max_heart_rate", nullable = false)
    var maxHeartRate: Int = 0,

    @Column(name = "sprint_count", nullable = false)
    var sprintCount: Int = 0,

    @Column(name = "active_energy_kcal", nullable = false)
    var activeEnergyKcal: Int = 0,
)
