package com.opixxx.kicklog.common.security

import com.fasterxml.jackson.databind.ObjectMapper
import com.opixxx.kicklog.common.exception.ErrorCode
import com.opixxx.kicklog.common.exception.KickLogException
import java.nio.charset.StandardCharsets
import java.time.Clock
import java.time.Instant
import java.time.ZoneOffset
import java.util.Base64
import javax.crypto.Mac
import javax.crypto.spec.SecretKeySpec
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith

/**
 * EXEC_PLAN 2026-06-10 audit-fixes P3 — JwtTokenProvider.verify 의 sub safe cast.
 *
 * 기존 정상 토큰 검증은 [JwtTokenProviderTest] 가 담당한다 (회귀 기준선, 수정하지 않는다).
 * 본 테스트는 payload 의 sub 가 비정상(비숫자/누락/숫자 타입)일 때
 * ClassCastException / NumberFormatException 이 누출되지 않고
 * 도메인 예외(AUTH_INVALID_TOKEN)로 변환되는지를 검증한다.
 */
class JwtTokenProviderVerifyTest {

    private val secret = "test-secret-test-secret-test-secret-test-secret"
    private val issuer = "kicklog"
    private val audience = "kicklog-ios"
    private val objectMapper = ObjectMapper()
    private val encoder = Base64.getUrlEncoder().withoutPadding()
    private val fixedNow: Instant = Instant.parse("2026-06-10T00:00:00Z")
    private val clock: Clock = Clock.fixed(fixedNow, ZoneOffset.UTC)

    private val provider = JwtTokenProvider(
        properties = JwtProperties(
            secret = secret,
            issuer = issuer,
            audience = audience,
            accessTokenMinutes = 15,
            refreshTokenDays = 30,
        ),
        objectMapper = objectMapper,
        clock = clock,
    )

    @Test
    fun `sub 가 비숫자 문자열이면 AUTH_INVALID_TOKEN 으로 거부한다`() {
        // "abc" 처럼 toLong() 이 불가능한 sub → NumberFormatException 누출 금지
        val token = signToken(basePayload(sub = "abc"))

        val exception = assertFailsWith<KickLogException> {
            provider.verifyAccessToken(token)
        }
        assertEquals(ErrorCode.AUTH_INVALID_TOKEN, exception.errorCode)
    }

    @Test
    fun `sub 클레임이 누락되면 AUTH_INVALID_TOKEN 으로 거부한다`() {
        // sub 자체가 없는 토큰 → null cast(as String) 시 ClassCastException 누출 금지
        val token = signToken(basePayload(sub = null))

        val exception = assertFailsWith<KickLogException> {
            provider.verifyAccessToken(token)
        }
        assertEquals(ErrorCode.AUTH_INVALID_TOKEN, exception.errorCode)
    }

    @Test
    fun `sub 가 문자열이 아닌 숫자 타입이면 AUTH_INVALID_TOKEN 으로 거부한다`() {
        // sub 가 JSON number(123) 로 들어오면 (as String) cast 가 ClassCastException → 누출 금지
        val token = signToken(basePayload(subRaw = 123))

        val exception = assertFailsWith<KickLogException> {
            provider.verifyAccessToken(token)
        }
        assertEquals(ErrorCode.AUTH_INVALID_TOKEN, exception.errorCode)
    }

    /**
     * 정상 issuer/audience/exp/type 을 갖되 sub 만 비정상으로 설정한 payload.
     * sub 를 String 으로 지정하려면 [sub], 비-String raw 값(숫자 등)으로 넣으려면 [subRaw],
     * 둘 다 null 이면 sub 키 자체를 생략한다.
     */
    private fun basePayload(sub: String? = "1", subRaw: Any? = null): Map<String, Any> {
        val exp = fixedNow.plusSeconds(900).epochSecond
        val iat = fixedNow.epochSecond
        return buildMap {
            put("iss", issuer)
            put("aud", audience)
            put("iat", iat)
            put("exp", exp)
            put("type", "access")
            when {
                subRaw != null -> put("sub", subRaw)
                sub != null -> put("sub", sub)
                // 둘 다 null → sub 키 누락
            }
        }
    }

    private fun signToken(payload: Map<String, Any>): String {
        val header = mapOf("alg" to "HS256", "typ" to "JWT")
        val headerPart = encode(header)
        val payloadPart = encode(payload)
        val unsigned = "$headerPart.$payloadPart"
        return "$unsigned.${sign(unsigned)}"
    }

    private fun encode(value: Any): String =
        encoder.encodeToString(objectMapper.writeValueAsBytes(value))

    private fun sign(value: String): String {
        val mac = Mac.getInstance("HmacSHA256")
        mac.init(SecretKeySpec(secret.toByteArray(StandardCharsets.UTF_8), "HmacSHA256"))
        return encoder.encodeToString(mac.doFinal(value.toByteArray(StandardCharsets.UTF_8)))
    }
}
