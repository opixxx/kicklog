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
)
