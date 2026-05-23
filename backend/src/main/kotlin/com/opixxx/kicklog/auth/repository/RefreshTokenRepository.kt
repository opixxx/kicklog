package com.opixxx.kicklog.auth.repository

import com.opixxx.kicklog.auth.entity.RefreshToken
import org.springframework.data.jpa.repository.JpaRepository
import org.springframework.data.jpa.repository.Query
import java.util.UUID

interface RefreshTokenRepository : JpaRepository<RefreshToken, UUID>, RefreshTokenStore {
    override fun findByJti(jti: UUID): RefreshToken?

    @Query("select r from RefreshToken r where r.user.id = :userId and r.revokedAt is null")
    override fun findActiveByUserId(userId: Long): List<RefreshToken>
}
