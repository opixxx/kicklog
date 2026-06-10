package com.opixxx.kicklog.auth.repository

import com.opixxx.kicklog.auth.entity.RefreshToken
import java.time.Instant
import java.util.UUID

interface RefreshTokenStore {
    fun save(refreshToken: RefreshToken): RefreshToken
    fun findByJti(jti: UUID): RefreshToken?
    fun findActiveByUserId(userId: Long): List<RefreshToken>

    // 만료된 토큰 벌크 삭제 — 경계는 strict less than (expiresAt == now 는 보존). 삭제 건수 반환.
    fun deleteAllExpiredBefore(now: Instant): Int
}
