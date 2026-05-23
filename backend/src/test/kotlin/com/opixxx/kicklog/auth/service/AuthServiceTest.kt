package com.opixxx.kicklog.auth.service

import com.opixxx.kicklog.auth.entity.OAuthProvider
import com.opixxx.kicklog.auth.repository.InMemoryOAuthIdentityRepository
import com.opixxx.kicklog.auth.repository.InMemoryRefreshTokenRepository
import com.opixxx.kicklog.common.exception.ErrorCode
import com.opixxx.kicklog.common.exception.KickLogException
import com.opixxx.kicklog.common.security.JwtProperties
import com.opixxx.kicklog.common.security.JwtTokenProvider
import com.opixxx.kicklog.user.repository.InMemoryUserRepository
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertNotEquals
import kotlin.test.assertTrue

class AuthServiceTest {

    private val jwtTokenProvider = JwtTokenProvider(
        properties = JwtProperties(
            secret = "test-secret-test-secret-test-secret-test-secret",
            issuer = "kicklog",
            audience = "kicklog-ios",
            accessTokenMinutes = 15,
            refreshTokenDays = 30,
        ),
    )
    private val userRepository = InMemoryUserRepository()
    private val oauthIdentityRepository = InMemoryOAuthIdentityRepository()
    private val refreshTokenRepository = InMemoryRefreshTokenRepository()
    private val authService = AuthService(
        userRepository = userRepository,
        oauthIdentityRepository = oauthIdentityRepository,
        refreshTokenRepository = refreshTokenRepository,
        jwtTokenProvider = jwtTokenProvider,
    )

    @Test
    fun `카카오 신규 로그인은 사용자와 활성 refresh token을 만든다`() {
        val response = authService.signIn(
            provider = OAuthProvider.KAKAO,
            providerUserId = "12345",
            email = "kakao@example.com",
            displayNameHint = "조축러",
        )

        val refreshClaims = jwtTokenProvider.verifyRefreshToken(response.refreshToken)

        assertEquals("조축러", response.user.displayName)
        assertEquals(1, userRepository.count())
        assertTrue(refreshTokenRepository.findByJti(refreshClaims.jti!!)!!.isActive())
    }

    @Test
    fun `refresh는 기존 refresh token을 폐기하고 새 refresh token을 발급한다`() {
        val signIn = authService.signIn(
            provider = OAuthProvider.KAKAO,
            providerUserId = "12345",
            email = null,
            displayNameHint = "사용자",
        )

        val refreshed = authService.refresh(signIn.refreshToken)

        val oldJti = jwtTokenProvider.verifyRefreshToken(signIn.refreshToken).jti!!
        val newJti = jwtTokenProvider.verifyRefreshToken(refreshed.refreshToken).jti!!
        assertNotEquals(oldJti, newJti)
        assertTrue(refreshTokenRepository.findByJti(oldJti)!!.isRevoked())
        assertTrue(refreshTokenRepository.findByJti(newJti)!!.isActive())
    }

    @Test
    fun `폐기된 refresh token 재사용은 모든 활성 세션을 폐기한다`() {
        val signIn = authService.signIn(
            provider = OAuthProvider.KAKAO,
            providerUserId = "12345",
            email = null,
            displayNameHint = "사용자",
        )
        authService.refresh(signIn.refreshToken)

        val exception = assertFailsWith<KickLogException> {
            authService.refresh(signIn.refreshToken)
        }

        assertEquals(ErrorCode.AUTH_REFRESH_REUSED, exception.errorCode)
        assertTrue(refreshTokenRepository.findActiveByUserId(signIn.user.id).isEmpty())
    }
}
