package com.opixxx.kicklog.match.entity

import com.opixxx.kicklog.match.service.UpsertQuarterCommand
import jakarta.persistence.Column
import jakarta.persistence.Entity
import jakarta.persistence.FetchType
import jakarta.persistence.GeneratedValue
import jakarta.persistence.GenerationType
import jakarta.persistence.Id
import jakarta.persistence.JoinColumn
import jakarta.persistence.ManyToOne
import jakarta.persistence.Table
import jakarta.persistence.UniqueConstraint
import java.time.Instant

@Entity
@Table(
    name = "quarter_workouts",
    // 운영 스키마(Flyway V5)의 제약을 엔티티에도 명시 — test 프로파일(H2 ddl-auto=create-drop)에서도
    // 동일 제약이 생성되어 "한 경기에 같은 쿼터 번호 중복" 회귀를 테스트가 잡을 수 있게 한다.
    uniqueConstraints = [
        UniqueConstraint(
            name = "quarter_workouts_match_id_quarter_number_key",
            columnNames = ["match_id", "quarter_number"],
        ),
    ],
)
class QuarterWorkout(
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    var id: Long = 0,

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "match_id", nullable = false)
    var match: Match,

    @Column(name = "quarter_number", nullable = false)
    var quarterNumber: Int,

    // 식별자 외 필드 기본값 — from() 팩토리가 생성 직후 updateFrom() 으로 채운다 (필드 매핑 단일화).
    @Column(name = "health_kit_workout_id", nullable = false)
    var healthKitWorkoutId: String = "",

    @Column(name = "started_at", nullable = false)
    var startedAt: Instant = Instant.EPOCH,

    @Column(name = "ended_at", nullable = false)
    var endedAt: Instant = Instant.EPOCH,

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
) {
    // 식별자(match·quarterNumber)는 그대로 두고 지표·시각 필드를 command 값으로 in-place 갱신한다.
    // Match.replaceQuarters 가 같은 (match_id, quarter_number) 쿼터를 재PUT 할 때 호출 —
    // 기존 행을 갈아엎지(DELETE+INSERT) 않아 unique 제약 충돌 없이 재계산/재라벨링 결과를 반영한다.
    fun updateFrom(command: UpsertQuarterCommand) {
        healthKitWorkoutId = command.healthKitWorkoutId
        startedAt = command.startedAt
        endedAt = command.endedAt
        durationSeconds = command.durationSeconds
        distanceM = command.distanceM
        avgSpeedKmh = command.avgSpeedKmh
        maxSpeedKmh = command.maxSpeedKmh
        avgHeartRate = command.avgHeartRate
        maxHeartRate = command.maxHeartRate
        sprintCount = command.sprintCount
        activeEnergyKcal = command.activeEnergyKcal
    }

    companion object {
        // 신규 쿼터를 command 로부터 생성한다. 식별자만 생성자로 받고 나머지는 updateFrom 으로 채워
        // INSERT(신규)·UPDATE(갱신) 양쪽의 필드 매핑을 updateFrom 한 곳으로 단일화한다.
        fun from(match: Match, command: UpsertQuarterCommand): QuarterWorkout =
            QuarterWorkout(match = match, quarterNumber = command.quarterNumber)
                .apply { updateFrom(command) }
    }
}
