package com.opixxx.kicklog.match.repository

/*
 * 시즌 통계 집계 결과 — DB 에서 계산해 내려받는 값들.
 *
 * 애플리케이션이 1년치 Match 를 전부 메모리에 올려 합산하던 방식을 대체한다 (2026-09-16).
 * 경기 N 건이면 엔티티 N + 4N 개가 heap 에 생성되던 것을, 집계 결과 몇 행으로 줄인다.
 *
 * **집계 단위별로 타입이 나뉘어 있는 이유**: matches 와 quarter_workouts 를 조인해 한 번에
 * 집계하면 경기 1행이 쿼터 수만큼 복제되어 거리·골이 쿼터 개수배로 중복 합산된다(fan-out).
 * 단위를 섞지 않는 것이 값 정확성의 전제다.
 */


/** 경기(matches) 단위 집계. 쿼터와 조인하지 않는다. */
data class SeasonMatchAggregate(
    val totalDistanceM: Int,
    val totalGoals: Int,
    val totalAssists: Int,
    val matchCount: Int,
    val winCount: Int,
    val drawCount: Int,
    val lossCount: Int,
    val maxSpeedKmh: Double,
    val longestMatchDistanceM: Int,
    val mostSprintCount: Int,
) {
    companion object {
        // 위치 인자로 두면 필드 순서가 바뀔 때 조용히 어긋난다.
        val EMPTY = SeasonMatchAggregate(
            totalDistanceM = 0, totalGoals = 0, totalAssists = 0, matchCount = 0,
            winCount = 0, drawCount = 0, lossCount = 0,
            maxSpeedKmh = 0.0, longestMatchDistanceM = 0, mostSprintCount = 0,
        )
    }
}

/**
 * 쿼터(quarter_workouts) 단위 집계.
 *
 * 평균 심박은 나눗셈까지 SQL 에서 하지 않고 **분자·분모를 그대로 반환**한다.
 * 0 division 과 정수 버림을 SQL 로 처리하면 기존 Kotlin 구현과 반올림이 어긋날 위험이 있어,
 * 나눗셈은 호출부(SeasonStatService)가 담당한다.
 */
data class SeasonQuarterAggregate(
    val quarterCount: Int,
    /** SUM(avg_heart_rate × duration_seconds) — 가중평균의 분자 */
    val weightedHeartRateSum: Long,
    /** SUM(duration_seconds) — 가중평균의 분모 */
    val totalDurationSeconds: Long,
) {
    companion object {
        val EMPTY = SeasonQuarterAggregate(quarterCount = 0, weightedHeartRateSum = 0L, totalDurationSeconds = 0L)
    }
}

/** 월별 이동거리 한 행. [month] 는 1~12 (UTC `played_at` 기준 — api-spec §8.1). */
data class MonthlyDistance(
    val month: Int,
    val distanceM: Int,
)
