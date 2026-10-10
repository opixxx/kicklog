package com.opixxx.kicklog.testsupport

import com.opixxx.kicklog.match.entity.Match
import com.opixxx.kicklog.match.service.MatchPosition
import com.opixxx.kicklog.match.service.MatchResultType
import com.opixxx.kicklog.match.service.UpsertMatchCommand
import com.opixxx.kicklog.match.service.UpsertQuarterCommand
import java.time.Instant
import java.util.UUID

/**
 * EXEC_PLAN 2026-09-16 season-stat-sql-aggregation 전용 fixture.
 *
 * 기존 [ServiceTestFixtures.matchCommand] 는 **쿼터를 항상 1개만** 만들기 때문에
 * 조인 집계의 fan-out(경기 1행이 쿼터 수만큼 복제되어 경기 지표가 중복 합산되는 현상)을
 * 드러내지 못한다. 본 fixture 는 쿼터 개수·durationSeconds·심박을 자유롭게 지정할 수 있어
 * fan-out / 0 division / 빈 쿼터 / UTC 월 경계를 한 데이터셋에 섞을 수 있다.
 *
 * 기존 테스트의 기대값에 영향을 주지 않도록 **기존 fixture 는 건드리지 않고 별도 파일**로 둔다.
 */
object SeasonAggregateFixtures {

    /** 쿼터 1개의 사양. quarterNumber 는 목록 순서로 1..4 가 자동 부여된다. */
    data class QuarterSpec(
        val durationSeconds: Int = 900,
        val avgHeartRate: Int = 145,
        val distanceM: Int = 0,
        val sprintCount: Int = 0,
    )

    /** 경기 1건의 사양. `quarters` 가 비면 쿼터 없는 경기(빈 쿼터 케이스)가 된다. */
    data class MatchSpec(
        val playedAt: String,
        val totalDistanceM: Int = 0,
        val goals: Int = 0,
        val assists: Int = 0,
        val maxSpeedKmh: Double = 0.0,
        val sprintCount: Int = 0,
        val result: MatchResultType? = MatchResultType.WIN,
        val quarters: List<QuarterSpec> = emptyList(),
    )

    fun command(venueId: Long, spec: MatchSpec): UpsertMatchCommand {
        val playedAt = Instant.parse(spec.playedAt)
        // result 는 Match 가 (teamGoals, opponentGoals) 로 derive 한다 — 원하는 결과가 나오는 점수 쌍을 만든다.
        // DB CHECK(matches_team_goals_gte_user_goals) 때문에 teamGoals >= goals 를 반드시 지켜야 한다.
        val (teamGoals, opponentGoals) = when (spec.result) {
            MatchResultType.WIN -> maxOf(spec.goals, 1) to 0
            MatchResultType.DRAW -> spec.goals to spec.goals
            MatchResultType.LOSS -> spec.goals to spec.goals + 1
            null -> null to null
        }
        return UpsertMatchCommand(
            venueId = venueId,
            playedAt = playedAt,
            opponent = "OO FC",
            position = MatchPosition.MF,
            goals = spec.goals,
            assists = spec.assists,
            opponentGoals = opponentGoals,
            teamGoals = teamGoals,
            totalDistanceM = spec.totalDistanceM,
            maxSpeedKmh = spec.maxSpeedKmh,
            sprintCount = spec.sprintCount,
            avgHeartRate = 0,
            quarters = spec.quarters.mapIndexed { index, quarter ->
                quarterCommand(playedAt, index + 1, quarter)
            },
        )
    }

    /**
     * 같은 사양으로 Match 엔티티를 만든다.
     *
     * InMemory / JPA 두 저장소에 **같은 데이터**를 넣어야 하므로 호출할 때마다 새 인스턴스를 만든다
     * (JPA 에 저장된 managed 엔티티를 인메모리에 재사용하면 동등성 비교가 오염된다).
     */
    fun match(userId: Long, venueId: Long, spec: MatchSpec): Match {
        return Match.create(userId, UUID.randomUUID(), command(venueId, spec))
    }

    private fun quarterCommand(playedAt: Instant, quarterNumber: Int, spec: QuarterSpec): UpsertQuarterCommand {
        return UpsertQuarterCommand(
            quarterNumber = quarterNumber,
            healthKitWorkoutId = "hk-${UUID.randomUUID()}",
            startedAt = playedAt,
            endedAt = playedAt.plusSeconds(spec.durationSeconds.toLong()),
            durationSeconds = spec.durationSeconds,
            distanceM = spec.distanceM,
            avgSpeedKmh = 0.0,
            maxSpeedKmh = 0.0,
            avgHeartRate = spec.avgHeartRate,
            maxHeartRate = spec.avgHeartRate + 10,
            sprintCount = spec.sprintCount,
            activeEnergyKcal = 0,
        )
    }
}
