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

    // 시즌 집계 전용 — 페이지네이션 없으므로 컬렉션 fetch join 안전 (N+1 제거).
    // quarterWorkouts 가 JPA 영속 필드 (quarters 는 정렬 getter — HQL 경로 아님).
    @Query(
        """
        SELECT DISTINCT m
        FROM Match m
        LEFT JOIN FETCH m.quarterWorkouts
        WHERE m.userId = :userId
          AND m.playedAt >= :startInclusive
          AND m.playedAt < :endExclusive
        ORDER BY m.playedAt DESC, m.id DESC
        """,
    )
    fun findAllByUserIdAndPlayedAtBetween(
        @Param("userId") userId: Long,
        @Param("startInclusive") startInclusive: Instant,
        @Param("endExclusive") endExclusive: Instant,
    ): List<Match>

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
