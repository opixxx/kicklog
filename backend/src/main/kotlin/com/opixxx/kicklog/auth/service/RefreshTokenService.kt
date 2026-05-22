package com.opixxx.kicklog.auth.service

import com.opixxx.kicklog.auth.entity.RefreshToken
import com.opixxx.kicklog.auth.repository.RefreshTokenRepository
import com.opixxx.kicklog.common.security.JwtTokenProvider
import com.opixxx.kicklog.common.security.ParsedJwt
import com.opixxx.kicklog.user.entity.User
import com.opixxx.kicklog.user.repository.UserRepository
import org.springframework.beans.factory.annotation.Value
import org.springframework.stereotype.Service
import org.springframework.transaction.annotation.Transactional
import java.time.Clock
import java.time.Duration
import java.util.UUID

@Service
class RefreshTokenService(
    private val refreshTokenRepository: RefreshTokenRepository,
    private val userRepository: UserRepository,
    private val jwtTokenProvider: JwtTokenProvider,
    private val clock: Clock,
    @Value("\${kicklog.jwt.refresh-expiration-days}") refreshExpirationDays: Long,
) {
    private val refreshTtl: Duration = Duration.ofDays(refreshExpirationDays)

    @Transactional
    fun issue(user: User): String {
        val jti = UUID.randomUUID()
        val expiresAt = clock.instant().plus(refreshTtl)
        refreshTokenRepository.save(
            RefreshToken(
                jti = jti,
                userId = user.id,
                expiresAt = expiresAt,
            ),
        )
        return jwtTokenProvider.createRefreshToken(user.id, jti, expiresAt)
    }

    @Transactional(readOnly = true)
    fun validate(refreshToken: String): User {
        val parsed = parseRefreshToken(refreshToken)
        if (parsed.type != JwtTokenProvider.REFRESH_TYPE || parsed.jti == null) {
            throw InvalidRefreshTokenException()
        }

        val stored = findStoredRefreshToken(parseJti(parsed.jti))
        if (stored.revokedAt != null) throw InvalidRefreshTokenException()
        if (!stored.expiresAt.isAfter(clock.instant())) throw ExpiredRefreshTokenException()
        if (stored.userId.toString() != parsed.subject) throw InvalidRefreshTokenException()

        return userRepository.findById(stored.userId)
            .orElseThrow { InvalidRefreshTokenException() }
    }

    private fun findStoredRefreshToken(jti: UUID): RefreshToken =
        refreshTokenRepository.findById(jti)
            .orElseThrow { InvalidRefreshTokenException() }

    private fun parseRefreshToken(refreshToken: String): ParsedJwt =
        try {
            jwtTokenProvider.verify(refreshToken)
        } catch (exception: AuthException) {
            throw InvalidRefreshTokenException()
        }

    private fun parseJti(jti: String): UUID =
        try {
            UUID.fromString(jti)
        } catch (exception: IllegalArgumentException) {
            throw InvalidRefreshTokenException()
        }
}
