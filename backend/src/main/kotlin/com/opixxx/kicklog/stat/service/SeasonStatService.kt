package com.opixxx.kicklog.stat.service

import com.opixxx.kicklog.friend.service.FriendshipAuthorizer
import com.opixxx.kicklog.match.repository.MatchStore
import com.opixxx.kicklog.match.repository.MonthlyDistance
import com.opixxx.kicklog.match.repository.SeasonQuarterAggregate
import org.springframework.stereotype.Service
import org.springframework.transaction.annotation.Isolation
import org.springframework.transaction.annotation.Transactional
import java.time.LocalDate
import java.time.ZoneOffset

data class SeasonBest(
    val maxSpeedKmh: Double,
    val longestMatchDistanceM: Int,
    val mostSprintCount: Int,
)

data class SeasonStat(
    val year: Int,
    val totalDistanceM: Int,
    val totalGoals: Int,
    val totalAssists: Int,
    val matchCount: Int,
    val quarterCount: Int,
    val winCount: Int,
    val drawCount: Int,
    val lossCount: Int,
    val avgHeartRate: Int,
    val monthlyDistanceM: List<Int>,        // 12개. 1월(index 0) ~ 12월(index 11). UTC playedAt 기준.
    val best: SeasonBest,
)

@Service
class SeasonStatService(
    private val matchStore: MatchStore,
    private val friendshipAuthorizer: FriendshipAuthorizer,
) {
    // REPEATABLE_READ 인 이유: 집계 쿼리가 3개로 나뉘어 있어서다.
    // 기본 격리(READ COMMITTED)에서는 statement 마다 스냅샷이 갱신되므로, 조회 도중 다른
    // 트랜잭션이 경기를 커밋하면 matchCount 는 2 인데 quarterCount 는 3번째 경기의 쿼터까지
    // 포함하는 자기모순 응답이 나갈 수 있다 (월별 합 ≠ 총거리도 같은 원인).
    // 전환 전에는 쿼리가 1개라 원자적이었으므로, 동작 보존을 위해 세 쿼리를 한 스냅샷에 묶는다.
    // PostgreSQL 의 readOnly 트랜잭션에서 REPEATABLE_READ 는 추가 잠금이 없어 비용이 사실상 없다.
    @Transactional(readOnly = true, isolation = Isolation.REPEATABLE_READ)
    fun getMySeasonStat(userId: Long, year: Int): SeasonStat {
        return calculate(userId, year)
    }

    @Transactional(readOnly = true, isolation = Isolation.REPEATABLE_READ)
    fun getFriendSeasonStat(viewerId: Long, friendUserId: Long, year: Int): SeasonStat {
        friendshipAuthorizer.assertCanView(viewerId, friendUserId)
        return calculate(friendUserId, year)
    }

    /**
     * 시즌 통계를 조합한다.
     *
     * 집계는 DB 가 한다 (2026-09-16 전환). 이전에는 1년치 Match 를 쿼터까지 fetch join 으로
     * 전부 메모리에 올려 sumOf/count/flatMap 으로 합산했고, 경기 N 건이면 엔티티 N + 4N 개가
     * heap 에 생성됐다. heap 상한을 224MB 로 낮춘 뒤로는 그 방식의 여유가 크지 않다.
     *
     * 집계 쿼리가 경기/쿼터/월별로 나뉘어 있는 이유는 fan-out 때문이다 — 두 테이블을 조인해
     * 한 번에 집계하면 경기 1행이 쿼터 수만큼 복제되어 거리·골이 중복 합산된다.
     */
    private fun calculate(userId: Long, year: Int): SeasonStat {
        val start = LocalDate.of(year, 1, 1).atStartOfDay().toInstant(ZoneOffset.UTC)
        val end = LocalDate.of(year + 1, 1, 1).atStartOfDay().toInstant(ZoneOffset.UTC)

        val matchAggregate = matchStore.aggregateSeasonMatches(userId, start, end)
        val quarterAggregate = matchStore.aggregateSeasonQuarters(userId, start, end)
        val monthly = matchStore.aggregateMonthlyDistance(userId, start, end)

        return SeasonStat(
            year = year,
            totalDistanceM = matchAggregate.totalDistanceM,
            totalGoals = matchAggregate.totalGoals,
            totalAssists = matchAggregate.totalAssists,
            matchCount = matchAggregate.matchCount,
            quarterCount = quarterAggregate.quarterCount,
            winCount = matchAggregate.winCount,
            drawCount = matchAggregate.drawCount,
            lossCount = matchAggregate.lossCount,
            avgHeartRate = weightedAvgHeartRate(quarterAggregate),
            monthlyDistanceM = toMonthlyArray(monthly),
            best = SeasonBest(
                maxSpeedKmh = matchAggregate.maxSpeedKmh,
                longestMatchDistanceM = matchAggregate.longestMatchDistanceM,
                mostSprintCount = matchAggregate.mostSprintCount,
            ),
        )
    }

    // duration 가중평균. 총 시간이 0 이면 0 (쿼터가 없거나 duration 이 전부 0 인 경우).
    // 나눗셈을 SQL 이 아니라 여기서 하는 이유: 0 division 과 정수 버림을 한 곳에서 명시적으로 다룬다.
    private fun weightedAvgHeartRate(aggregate: SeasonQuarterAggregate): Int {
        if (aggregate.totalDurationSeconds == 0L) return 0
        return (aggregate.weightedHeartRateSum / aggregate.totalDurationSeconds).toInt()
    }

    // 집계 결과는 데이터 있는 달만 담고 있다. 항상 12칸으로 채운다 (빈 월 0) — api-spec §8.1.
    private fun toMonthlyArray(monthly: List<MonthlyDistance>): List<Int> {
        val arr = IntArray(12)
        monthly.forEach { arr[it.month - 1] += it.distanceM }
        return arr.toList()
    }
}
