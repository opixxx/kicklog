package com.opixxx.kicklog.auth.repository

import com.opixxx.kicklog.auth.entity.RefreshToken
import java.util.UUID

interface RefreshTokenStore {
    fun save(refreshToken: RefreshToken): RefreshToken
    fun findByJti(jti: UUID): RefreshToken?
    fun findActiveByUserId(userId: Long): List<RefreshToken>
}
