package com.opixxx.kicklog.match.repository

/**
 * native 집계 쿼리의 결과를 받는 Spring Data 인터페이스 프로젝션.
 *
 * 쿼리의 컬럼 별칭은 따옴표로 감싸 대소문자를 보존한다 — PostgreSQL 은 따옴표 없는 식별자를
 * 소문자로 접기 때문에 별칭과 getter 이름이 어긋날 수 있다.
 *
 * **모든 수치 컬럼은 쿼리에서 `CAST(... AS bigint)` 로 타입을 못 박았다.** PostgreSQL 의 집계
 * 반환 타입이 함수마다 다르기 때문이다 — `SUM(integer)`·`COUNT(*)` 는 bigint 지만
 * `MAX(integer)` 는 integer, `SUM(bigint * integer)` 는 **numeric**(JDBC BigDecimal) 이다.
 * 캐스팅이 없으면 Spring 의 ConversionService 가 암묵 변환해 줘서 인터페이스 프로젝션은 통과하지만,
 * 나중에 생성자 프로젝션(data class)이나 Tuple 직접 매핑으로 바꾸는 순간 ClassCastException 이 된다.
 * 타입을 SQL 에서 고정해 그 잠복 결함을 없앤다.
 */
interface SeasonMatchAggregateRow {
    val totalDistanceM: Long
    val totalGoals: Long
    val totalAssists: Long
    val matchCount: Long
    val winCount: Long
    val drawCount: Long
    val lossCount: Long
    val maxSpeedKmh: Double
    val longestMatchDistanceM: Long
    val mostSprintCount: Long
}

interface SeasonQuarterAggregateRow {
    val quarterCount: Long
    val weightedHeartRateSum: Long
    val totalDurationSeconds: Long
}

interface MonthlyDistanceRow {
    val month: Int
    val distanceM: Long
}
