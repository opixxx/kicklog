package com.opixxx.kicklog.auth.repository

import com.opixxx.kicklog.auth.entity.RefreshToken
import org.springframework.data.jpa.repository.JpaRepository
import org.springframework.data.jpa.repository.Modifying
import org.springframework.data.jpa.repository.Query
import org.springframework.data.repository.query.Param
import org.springframework.transaction.annotation.Transactional
import java.time.Instant
import java.util.UUID

interface RefreshTokenRepository : JpaRepository<RefreshToken, UUID>, RefreshTokenStore {
    override fun findByJti(jti: UUID): RefreshToken?

    @Query("select r from RefreshToken r where r.user.id = :userId and r.revokedAt is null")
    override fun findActiveByUserId(userId: Long): List<RefreshToken>

    // 자체 트랜잭션 — 스케줄러/테스트가 외부 트랜잭션 없이 호출해도 안전하게 실행된다.
    @Modifying
    @Transactional
    @Query("delete from RefreshToken r where r.expiresAt < :now")
    override fun deleteAllExpiredBefore(@Param("now") now: Instant): Int
}
