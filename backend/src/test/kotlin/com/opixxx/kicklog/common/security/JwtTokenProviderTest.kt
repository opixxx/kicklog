package com.opixxx.kicklog.common.security

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertTrue

class JwtTokenProviderTest {

    private val provider = JwtTokenProvider(
        properties = JwtProperties(
            secret = "test-secret-test-secret-test-secret-test-secret",
            issuer = "kicklog",
            audience = "kicklog-ios",
            accessTokenMinutes = 15,
            refreshTokenDays = 30,
        ),
    )

    @Test
    fun `access token은 15분 만료와 access 타입 클레임을 가진다`() {
        val token = provider.createAccessToken(userId = 1L)

        val claims = provider.verifyAccessToken(token)

        assertEquals(1L, claims.userId)
        assertEquals(TokenType.ACCESS, claims.type)
        assertTrue(claims.expiresAt.isAfter(claims.issuedAt))
        assertEquals(15, java.time.Duration.between(claims.issuedAt, claims.expiresAt).toMinutes())
    }

    @Test
    fun `refresh token은 30일 만료와 jti를 가진다`() {
        val token = provider.createRefreshToken(userId = 1L)

        val claims = provider.verifyRefreshToken(token)

        assertEquals(1L, claims.userId)
        assertEquals(TokenType.REFRESH, claims.type)
        assertNotNull(claims.jti)
        assertEquals(30, java.time.Duration.between(claims.issuedAt, claims.expiresAt).toDays())
    }
}
