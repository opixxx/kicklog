package com.opixxx.kicklog.common.security

import com.fasterxml.jackson.core.type.TypeReference
import com.fasterxml.jackson.databind.ObjectMapper
import com.opixxx.kicklog.common.exception.ErrorCode
import com.opixxx.kicklog.common.exception.KickLogException
import org.springframework.stereotype.Component
import java.nio.charset.StandardCharsets
import java.time.Clock
import java.time.Duration
import java.time.Instant
import java.util.Base64
import java.util.UUID
import javax.crypto.Mac
import javax.crypto.spec.SecretKeySpec

enum class TokenType {
    ACCESS,
    REFRESH,
}

data class JwtClaims(
    val userId: Long,
    val type: TokenType,
    val issuedAt: Instant,
    val expiresAt: Instant,
    val jti: UUID?,
)

@Component
class JwtTokenProvider(
    private val properties: JwtProperties,
    private val objectMapper: ObjectMapper = ObjectMapper(),
    private val clock: Clock = Clock.systemUTC(),
) {
    private val encoder = Base64.getUrlEncoder().withoutPadding()
    private val decoder = Base64.getUrlDecoder()

    fun createAccessToken(userId: Long): String {
        return createToken(userId, TokenType.ACCESS, Duration.ofMinutes(properties.accessTokenMinutes), null)
    }

    fun createRefreshToken(userId: Long, jti: UUID = UUID.randomUUID()): String {
        return createToken(userId, TokenType.REFRESH, Duration.ofDays(properties.refreshTokenDays), jti)
    }

    fun verifyAccessToken(token: String): JwtClaims {
        val claims = verify(token)
        if (claims.type != TokenType.ACCESS) {
            throw KickLogException(ErrorCode.AUTH_INVALID_TOKEN)
        }
        return claims
    }

    fun verifyRefreshToken(token: String): JwtClaims {
        val claims = verify(token)
        if (claims.type != TokenType.REFRESH || claims.jti == null) {
            throw KickLogException(ErrorCode.AUTH_INVALID_REFRESH)
        }
        return claims
    }

    private fun createToken(userId: Long, type: TokenType, ttl: Duration, jti: UUID?): String {
        val now = Instant.now(clock)
        val expiresAt = now.plus(ttl)
        val header = mapOf("alg" to "HS256", "typ" to "JWT")
        val payload = buildMap<String, Any> {
            put("sub", userId.toString())
            put("iss", properties.issuer)
            put("aud", properties.audience)
            put("iat", now.epochSecond)
            put("exp", expiresAt.epochSecond)
            put("type", type.name.lowercase())
            if (jti != null) put("jti", jti.toString())
        }
        val headerPart = encodeJson(header)
        val payloadPart = encodeJson(payload)
        val unsigned = "$headerPart.$payloadPart"
        return "$unsigned.${sign(unsigned)}"
    }

    private fun verify(token: String): JwtClaims {
        val parts = token.split(".")
        if (parts.size != 3) {
            throw KickLogException(ErrorCode.AUTH_INVALID_TOKEN)
        }
        val unsigned = "${parts[0]}.${parts[1]}"
        if (!constantTimeEquals(sign(unsigned), parts[2])) {
            throw KickLogException(ErrorCode.AUTH_INVALID_TOKEN)
        }

        val payload = parseJson(parts[1])
        if (payload["iss"] != properties.issuer || payload["aud"] != properties.audience) {
            throw KickLogException(ErrorCode.AUTH_INVALID_TOKEN)
        }

        val expiresAt = Instant.ofEpochSecond((payload["exp"] as Number).toLong())
        if (!expiresAt.isAfter(Instant.now(clock))) {
            throw KickLogException(ErrorCode.AUTH_EXPIRED_TOKEN)
        }

        val type = when (payload["type"]) {
            "access" -> TokenType.ACCESS
            "refresh" -> TokenType.REFRESH
            else -> throw KickLogException(ErrorCode.AUTH_INVALID_TOKEN)
        }

        return JwtClaims(
            userId = (payload["sub"] as String).toLong(),
            type = type,
            issuedAt = Instant.ofEpochSecond((payload["iat"] as Number).toLong()),
            expiresAt = expiresAt,
            jti = (payload["jti"] as String?)?.let(UUID::fromString),
        )
    }

    private fun encodeJson(value: Any): String {
        return encoder.encodeToString(objectMapper.writeValueAsBytes(value))
    }

    private fun parseJson(value: String): Map<String, Any?> {
        val bytes = decoder.decode(value)
        return objectMapper.readValue(bytes, object : TypeReference<Map<String, Any?>>() {})
    }

    private fun sign(value: String): String {
        val mac = Mac.getInstance("HmacSHA256")
        mac.init(SecretKeySpec(properties.secret.toByteArray(StandardCharsets.UTF_8), "HmacSHA256"))
        return encoder.encodeToString(mac.doFinal(value.toByteArray(StandardCharsets.UTF_8)))
    }

    private fun constantTimeEquals(left: String, right: String): Boolean {
        return java.security.MessageDigest.isEqual(
            left.toByteArray(StandardCharsets.UTF_8),
            right.toByteArray(StandardCharsets.UTF_8),
        )
    }
}
