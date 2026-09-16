package com.opixxx.kicklog.match.repository

import com.opixxx.kicklog.match.entity.Match
import org.springframework.data.domain.Pageable
import org.springframework.data.jpa.repository.JpaRepository
import org.springframework.data.jpa.repository.Modifying
import org.springframework.data.jpa.repository.Query
import org.springframework.data.repository.query.Param
import java.time.Instant
import java.util.UUID

interface MatchRepository : JpaRepository<Match, Long> {
    fun findByUserIdAndClientMatchId(userId: Long, clientMatchId: UUID): Match?

    @Query(
        """
        SELECT m
        FROM Match m
        WHERE m.userId = :userId
        ORDER BY m.playedAt DESC, m.id DESC
        """,
    )
    fun findFirstPageByUserId(
        @Param("userId") userId: Long,
        pageable: Pageable,
    ): List<Match>

    @Query(
        """
        SELECT m
        FROM Match m
        WHERE m.userId = :userId
          AND (
              m.playedAt < :cursorPlayedAt
              OR (m.playedAt = :cursorPlayedAt AND m.id < :cursorId)
          )
        ORDER BY m.playedAt DESC, m.id DESC
        """,
    )
    fun findAllByUserIdAfterCursor(
        @Param("userId") userId: Long,
        @Param("cursorPlayedAt") cursorPlayedAt: Instant,
        @Param("cursorId") cursorId: Long,
        pageable: Pageable,
    ): List<Match>

    // ─── 시즌 통계 집계 (2026-09-16) ────────────────────────────────
    // 1년치 Match 를 메모리로 올려 합산하던 방식을 DB 집계로 대체했다.
    // 세 쿼리로 나눈 이유는 fan-out 때문이다 — matches 와 quarter_workouts 를 조인해
    // 한 번에 집계하면 경기 1행이 쿼터 수만큼 복제되어 거리·골이 쿼터 개수배가 된다.
    //
    // 인덱스: idx_matches_user_played_at_id (user_id, played_at DESC, id DESC) — V5.
    // WHERE 가 (user_id, played_at) 접두사라 그대로 커버된다 (V7 의 중복 인덱스는 V15 에서 DROP).
    //
    // COALESCE 는 0 건일 때 SUM/MAX 가 NULL 을 반환해 Kotlin 비-null 타입 매핑이 깨지는 것을 막는다.

    /** 경기 단위 집계 — quarter_workouts 와 조인하지 않는다 (fan-out 회피). */
    @Query(
        value = """
        SELECT
            COALESCE(SUM(m.total_distance_m), 0)                  AS "totalDistanceM",
            COALESCE(SUM(m.goals), 0)                             AS "totalGoals",
            COALESCE(SUM(m.assists), 0)                           AS "totalAssists",
            COUNT(*)                                              AS "matchCount",
            COUNT(*) FILTER (WHERE m.result = 'WIN')              AS "winCount",
            COUNT(*) FILTER (WHERE m.result = 'DRAW')             AS "drawCount",
            COUNT(*) FILTER (WHERE m.result = 'LOSS')             AS "lossCount",
            COALESCE(MAX(m.max_speed_kmh), 0)                     AS "maxSpeedKmh",
            CAST(COALESCE(MAX(m.total_distance_m), 0) AS bigint)  AS "longestMatchDistanceM",
            CAST(COALESCE(MAX(m.sprint_count), 0) AS bigint)      AS "mostSprintCount"
        FROM matches m
        WHERE m.user_id = :userId
          AND m.played_at >= :startInclusive
          AND m.played_at <  :endExclusive
        """,
        nativeQuery = true,
    )
    fun aggregateSeasonMatches(
        @Param("userId") userId: Long,
        @Param("startInclusive") startInclusive: Instant,
        @Param("endExclusive") endExclusive: Instant,
    ): SeasonMatchAggregateRow

    /**
     * 쿼터 단위 집계 — 조인은 기간 필터 용도이고 집계 대상이 쿼터 하나뿐이라 fan-out 이 없다.
     * 심박은 나눗셈 없이 분자(가중합)·분모(총 duration)를 그대로 반환한다.
     */
    @Query(
        value = """
        SELECT
            COUNT(*)                                                        AS "quarterCount",
            CAST(COALESCE(SUM(CAST(q.avg_heart_rate AS bigint) * q.duration_seconds), 0) AS bigint) AS "weightedHeartRateSum",
            COALESCE(SUM(q.duration_seconds), 0)                            AS "totalDurationSeconds"
        FROM quarter_workouts q
        JOIN matches m ON m.id = q.match_id
        WHERE m.user_id = :userId
          AND m.played_at >= :startInclusive
          AND m.played_at <  :endExclusive
        """,
        nativeQuery = true,
    )
    fun aggregateSeasonQuarters(
        @Param("userId") userId: Long,
        @Param("startInclusive") startInclusive: Instant,
        @Param("endExclusive") endExclusive: Instant,
    ): SeasonQuarterAggregateRow

    /**
     * 월별 이동거리 — **UTC 고정**. api-spec §8.1 이 "UTC playedAt.month 기준" 으로 못 박았고
     * 기존 구현도 `playedAt.atZone(ZoneOffset.UTC).monthValue` 였다. AT TIME ZONE 을 빠뜨리면
     * 서버 타임존에 따라 경기가 다른 달로 집계된다.
     *
     * 데이터가 있는 달만 반환한다 — 12칸 배열로 채우는 것은 호출부 책임.
     */
    @Query(
        value = """
        SELECT
            CAST(EXTRACT(MONTH FROM m.played_at AT TIME ZONE 'UTC') AS int) AS "month",
            CAST(COALESCE(SUM(m.total_distance_m), 0) AS bigint)            AS "distanceM"
        FROM matches m
        WHERE m.user_id = :userId
          AND m.played_at >= :startInclusive
          AND m.played_at <  :endExclusive
        GROUP BY CAST(EXTRACT(MONTH FROM m.played_at AT TIME ZONE 'UTC') AS int)
        ORDER BY 1
        """,
        nativeQuery = true,
    )
    fun aggregateMonthlyDistance(
        @Param("userId") userId: Long,
        @Param("startInclusive") startInclusive: Instant,
        @Param("endExclusive") endExclusive: Instant,
    ): List<MonthlyDistanceRow>

    // 목록 2단계 로딩 — id 페이징 결과를 fetch join 으로 재조회 (커서 쿼리의 메모리 페이징 회피).
    @Query(
        """
        SELECT DISTINCT m
        FROM Match m
        LEFT JOIN FETCH m.quarterWorkouts
        WHERE m.id IN :ids
        ORDER BY m.playedAt DESC, m.id DESC
        """,
    )
    fun findAllWithQuartersByIdIn(@Param("ids") ids: List<Long>): List<Match>

    @Modifying(clearAutomatically = true, flushAutomatically = true)
    @Query("update Match m set m.venueId = null where m.venueId = :venueId")
    fun clearVenueId(@Param("venueId") venueId: Long): Int
}
