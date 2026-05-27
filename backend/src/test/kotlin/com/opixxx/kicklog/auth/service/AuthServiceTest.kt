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
    fun `signIn 가입 시 displayNameHint 충돌이 없으면 hint 를 그대로 사용한다`() {
        // 충돌 없는 hint 는 자동 suffix 없이 그대로 저장된다.
        val response = authService.signIn(
            provider = OAuthProvider.KAKAO,
            providerUserId = "kakao-fresh",
            email = null,
            displayNameHint = "축구초보",
        )

        assertEquals("축구초보", response.user.displayName)
    }

    @Test
    fun `signIn 가입 시 displayNameHint 가 활성 사용자에게 점유돼 있으면 자동 suffix 가 붙는다`() {
        // given: 기존 활성 사용자가 "축구왕" 점유
        userRepository.save(com.opixxx.kicklog.user.entity.User.create(displayName = "축구왕", email = null))

        // when: 신규 사용자가 같은 hint 로 가입
        val response = authService.signIn(
            provider = OAuthProvider.KAKAO,
            providerUserId = "kakao-new",
            email = null,
            displayNameHint = "축구왕",
        )

        // then: displayName 은 "축구왕-XXXX" (X = hex) 형태로 자동 변환
        val regex = Regex("^축구왕-[0-9A-Fa-f]{4}$")
        assertTrue(
            regex.matches(response.user.displayName),
            "displayName 자동 suffix 형식 위반 — 실제값=${response.user.displayName}",
        )
        // 두 사용자 모두 존재
        assertEquals(2, userRepository.count())
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
