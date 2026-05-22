package com.opixxx.kicklog.auth.service

import com.opixxx.kicklog.auth.dto.AuthUserResponse
import com.opixxx.kicklog.auth.dto.SignInResponse
import com.opixxx.kicklog.auth.dto.TokenResponse
import com.opixxx.kicklog.auth.entity.OAuthIdentity
import com.opixxx.kicklog.auth.entity.OAuthProvider
import com.opixxx.kicklog.auth.repository.OAuthIdentityRepository
import com.opixxx.kicklog.common.security.JwtTokenProvider
import com.opixxx.kicklog.user.entity.User
import com.opixxx.kicklog.user.repository.UserRepository
import org.springframework.beans.factory.annotation.Value
import org.springframework.stereotype.Service
import org.springframework.transaction.support.TransactionTemplate
import java.security.SecureRandom
import java.time.Clock
import java.time.Duration

@Service
class AuthService(
    private val kakaoOAuthGateway: KakaoOAuthGateway,
    private val oauthIdentityRepository: OAuthIdentityRepository,
    private val userRepository: UserRepository,
    private val jwtTokenProvider: JwtTokenProvider,
    private val refreshTokenService: RefreshTokenService,
    private val transactionTemplate: TransactionTemplate,
    private val clock: Clock,
    @Value("\${kicklog.jwt.access-expiration-hours}") accessExpirationHours: Long,
) {
    private val accessTtl: Duration = Duration.ofHours(accessExpirationHours)
    private val random = SecureRandom()

    fun signInWithKakao(kakaoAccessToken: String): SignInResponse {
        val kakaoUser = kakaoOAuthGateway.fetchUserInfo(kakaoAccessToken)
        return transactionTemplate.execute {
            val user = findOrCreateKakaoUser(kakaoUser)
            createSignInResponse(user)
        } ?: throw ExternalKakaoException("로그인 처리에 실패했습니다")
    }

    fun refresh(refreshToken: String): TokenResponse {
        val user = refreshTokenService.validate(refreshToken)
        val accessToken = jwtTokenProvider.createAccessToken(user.id, clock.instant().plus(accessTtl))
        return TokenResponse(accessToken = accessToken, refreshToken = refreshToken)
    }

    private fun findOrCreateKakaoUser(kakaoUser: KakaoUserInfo): User =
        findOAuthUser(OAuthProvider.KAKAO, kakaoUser.id)
            ?: createOAuthUser(
                provider = OAuthProvider.KAKAO,
                providerUserId = kakaoUser.id,
                email = kakaoUser.email,
                displayNameHint = kakaoUser.nickname?.takeIf { it.isNotBlank() } ?: "사용자",
            )

    private fun findOAuthUser(provider: OAuthProvider, providerUserId: String): User? {
        val identity = oauthIdentityRepository.findByProviderAndProviderUserId(provider, providerUserId)
            ?: return null
        return userRepository.findById(identity.userId).orElseThrow { InvalidRefreshTokenException() }
    }

    private fun createOAuthUser(
        provider: OAuthProvider,
        providerUserId: String,
        email: String?,
        displayNameHint: String,
    ): User {
        val user = userRepository.save(
            User(username = nextUsername(provider), displayName = displayNameHint.take(MAX_DISPLAY_NAME), email = email),
        )
        oauthIdentityRepository.save(OAuthIdentity(userId = user.id, provider = provider, providerUserId = providerUserId, email = email))
        return user
    }

    private fun createSignInResponse(user: User): SignInResponse {
        val accessToken = jwtTokenProvider.createAccessToken(user.id, clock.instant().plus(accessTtl))
        val refreshToken = refreshTokenService.issue(user)
        return SignInResponse(accessToken = accessToken, refreshToken = refreshToken, user = user.toAuthUserResponse())
    }

    private fun User.toAuthUserResponse(): AuthUserResponse =
        AuthUserResponse(id = id, displayName = displayName, email = email, hideHeartRate = hideHeartRate)

    private fun nextUsername(provider: OAuthProvider): String {
        repeat(USERNAME_RETRY_COUNT) {
            val candidate = "${provider.name.lowercase()}_${random.nextInt(USERNAME_RANDOM_BOUND)}"
            if (!userRepository.existsByUsername(candidate)) return candidate
        }
        throw ExternalKakaoException("사용자명을 생성하지 못했습니다")
    }

    companion object {
        private const val MAX_DISPLAY_NAME = 50
        private const val USERNAME_RETRY_COUNT = 10
        private const val USERNAME_RANDOM_BOUND = 1_000_000_000
    }
}
