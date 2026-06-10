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
import org.slf4j.LoggerFactory
import org.springframework.stereotype.Service
import org.springframework.transaction.annotation.Transactional
import java.security.SecureRandom
import java.time.Instant

@Service
class AuthService(
    private val userRepository: UserStore,
    private val oauthIdentityRepository: OAuthIdentityStore,
    private val refreshTokenRepository: RefreshTokenStore,
    private val jwtTokenProvider: JwtTokenProvider,
) {
    private val log = LoggerFactory.getLogger(javaClass)

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

        val user = saveUserWithUniqueDisplayName(displayNameHint ?: "사용자", email)
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

    // 가입 시 displayName 충돌 자동 suffix — base 점유면 "${base}-${hex4}" 로 최대 N회 재시도.
    // 응용 레벨 사전 조회만으로 결정 — `@Transactional(signIn)` 안에서 `DataIntegrityViolationException`
    // catch 후 retry 는 Hibernate 가 트랜잭션을 rollback-only 로 마킹해 안전하지 않다.
    // 운영 단계 ~2명 베타 컨텍스트에서 사전 select 통과 후 동시 race 확률 ~0 으로 허용.
    // race 발생 시 5xx 응답 — 운영 격상 시 별도 `DisplayNameAllocator` 빈 (`Propagation.REQUIRES_NEW`) 으로 격리 권장.
    private fun saveUserWithUniqueDisplayName(displayNameHint: String, email: String?): User {
        val base = displayNameHint.trim().takeIf { it.isNotEmpty() } ?: "사용자"
        // attempt 0 = base 1회, 1..MAX_DISPLAY_NAME_SUFFIX_RETRY = suffix 5회 — 총 6 attempts.
        for (attempt in 0..MAX_DISPLAY_NAME_SUFFIX_RETRY) {
            val candidate = if (attempt == 0) base else "$base-${randomHex4()}"
            if (userRepository.findActiveByDisplayName(candidate) == null) {
                return userRepository.save(User.create(candidate, email))
            }
            log.warn("displayName 충돌 — 후보 '{}' 점유됨 (attempt {}/{})", candidate, attempt, MAX_DISPLAY_NAME_SUFFIX_RETRY)
        }
        throw KickLogException(ErrorCode.INTERNAL_ERROR)
    }

    private fun randomHex4(): String {
        val bytes = ByteArray(2)
        secureRandom.nextBytes(bytes)
        return bytes.joinToString("") { "%02X".format(it) }
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

    companion object {
        private const val MAX_DISPLAY_NAME_SUFFIX_RETRY = 5
        private val secureRandom = SecureRandom()
    }
}
