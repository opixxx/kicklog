package com.opixxx.kicklog.auth.repository

import com.opixxx.kicklog.auth.entity.RefreshToken
import java.util.UUID

class InMemoryRefreshTokenRepository : RefreshTokenStore {
    private val refreshTokens = linkedMapOf<UUID, RefreshToken>()

    override fun save(refreshToken: RefreshToken): RefreshToken {
        refreshTokens[refreshToken.jti] = refreshToken
        return refreshToken
    }

    override fun findByJti(jti: UUID): RefreshToken? = refreshTokens[jti]

    override fun findActiveByUserId(userId: Long): List<RefreshToken> {
        return refreshTokens.values.filter { it.user.id == userId && it.isActive() }
    }
}
