package com.opixxx.kicklog.auth.service

import com.opixxx.kicklog.auth.dto.SignInResponse
import com.opixxx.kicklog.auth.dto.TokenResponse
import com.opixxx.kicklog.auth.entity.OAuthIdentity
import com.opixxx.kicklog.auth.entity.OAuthProvider
import com.opixxx.kicklog.auth.entity.RefreshToken
import com.opixxx.kicklog.auth.repository.OAuthIdentityStore
import com.opixxx.kicklog.auth.repository.RefreshTokenStore
import com.opixxx.kicklog.common.exception.ErrorCode
import com.opixxx.kicklog.common.exception.KickLogException
import com.opixxx.kicklog.common.security.JwtTokenProvider
import com.opixxx.kicklog.user.dto.UserResponse
import com.opixxx.kicklog.user.entity.User
import com.opixxx.kicklog.user.repository.UserStore
import org.springframework.stereotype.Service
import org.springframework.transaction.annotation.Transactional
import java.time.Instant

@Service
class AuthService(
    private val userRepository: UserStore,
    private val oauthIdentityRepository: OAuthIdentityStore,
    private val refreshTokenRepository: RefreshTokenStore,
    private val jwtTokenProvider: JwtTokenProvider,
) {
    @Transactional
    fun signIn(
        provider: OAuthProvider,
        providerUserId: String,
        email: String?,
        displayNameHint: String?,
    ): SignInResponse {
        val user = findOrCreateUser(provider, providerUserId, email, displayNameHint)
        val accessToken = jwtTokenProvider.createAccessToken(user.id)
        val refreshToken = jwtTokenProvider.createRefreshToken(user.id)
        val refreshClaims = jwtTokenProvider.verifyRefreshToken(refreshToken)

        refreshTokenRepository.save(
            RefreshToken(
                jti = refreshClaims.jti!!,
                user = user,
                expiresAt = refreshClaims.expiresAt,
            ),
        )

        return SignInResponse(accessToken, refreshToken, UserResponse.from(user))
    }

    @Transactional
    fun refresh(refreshToken: String): TokenResponse {
        val claims = verifyRefreshClaims(refreshToken)
        val stored = refreshTokenRepository.findByJti(claims.jti!!)
            ?: throw KickLogException(ErrorCode.AUTH_INVALID_REFRESH)

        validateRefreshToken(stored)

        val newAccessToken = jwtTokenProvider.createAccessToken(stored.user.id)
        val newRefreshToken = rotateRefreshToken(stored)

        return TokenResponse(newAccessToken, newRefreshToken)
    }

    @Transactional
    fun logout(userId: Long) {
        revokeAll(userId)
    }

    @Transactional
    fun logoutThisDevice(userId: Long, refreshToken: String) {
        val claims = verifyRefreshClaims(refreshToken)
        val stored = refreshTokenRepository.findByJti(claims.jti!!)
            ?: throw KickLogException(ErrorCode.AUTH_INVALID_REFRESH)
        if (stored.user.id != userId) {
            throw KickLogException(ErrorCode.AUTH_REFRESH_NOT_OWNED)
        }
        stored.revoke()
        refreshTokenRepository.save(stored)
    }

    private fun findOrCreateUser(
        provider: OAuthProvider,
        providerUserId: String,
        email: String?,
        displayNameHint: String?,
    ): User {
        val existing = oauthIdentityRepository.findByProviderAndProviderUserId(provider, providerUserId)
        if (existing != null) {
            return existing.user
        }

        val user = userRepository.save(User.create(displayNameHint ?: "사용자", email))
        oauthIdentityRepository.save(
            OAuthIdentity(
                user = user,
                provider = provider,
                providerUserId = providerUserId,
                email = email,
            ),
        )
        return user
    }

    private fun verifyRefreshClaims(refreshToken: String) = try {
        jwtTokenProvider.verifyRefreshToken(refreshToken)
    } catch (exception: KickLogException) {
        if (exception.errorCode == ErrorCode.AUTH_EXPIRED_TOKEN) {
            throw KickLogException(ErrorCode.AUTH_EXPIRED_REFRESH)
        }
        throw KickLogException(ErrorCode.AUTH_INVALID_REFRESH)
    }

    private fun validateRefreshToken(stored: RefreshToken) {
        if (stored.isRevoked()) {
            revokeAll(stored.user.id)
            throw KickLogException(ErrorCode.AUTH_REFRESH_REUSED)
        }
        if (stored.isExpired()) {
            throw KickLogException(ErrorCode.AUTH_EXPIRED_REFRESH)
        }
    }

    private fun rotateRefreshToken(stored: RefreshToken): String {
        val newRefreshToken = jwtTokenProvider.createRefreshToken(stored.user.id)
        val newClaims = jwtTokenProvider.verifyRefreshToken(newRefreshToken)

        stored.rotateTo(newClaims.jti!!)
        refreshTokenRepository.save(stored)
        refreshTokenRepository.save(
            RefreshToken(
                jti = newClaims.jti,
                user = stored.user,
                expiresAt = newClaims.expiresAt,
                createdAt = Instant.now(),
            ),
        )
        return newRefreshToken
    }

    private fun revokeAll(userId: Long) {
        refreshTokenRepository.findActiveByUserId(userId).forEach {
            it.revoke()
            refreshTokenRepository.save(it)
        }
    }
}
