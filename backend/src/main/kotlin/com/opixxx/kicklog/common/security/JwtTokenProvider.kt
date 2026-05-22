package com.opixxx.kicklog.common.security

import com.fasterxml.jackson.core.type.TypeReference
import com.fasterxml.jackson.databind.ObjectMapper
import com.opixxx.kicklog.auth.service.InvalidAccessTokenException
import com.opixxx.kicklog.auth.service.InvalidRefreshTokenException
import org.springframework.beans.factory.annotation.Value
import org.springframework.stereotype.Component
import java.nio.charset.StandardCharsets
import java.time.Clock
import java.time.Instant
import java.util.Base64
import java.util.UUID
import javax.crypto.Mac
import javax.crypto.spec.SecretKeySpec

data class ParsedJwt(
    val subject: String,
    val type: String,
    val expiresAt: Instant,
    val jti: String?,
)

@Component
class JwtTokenProvider(
    @Value("\${kicklog.jwt.secret}") private val secret: String,
    private val clock: Clock,
) {
    private val encoder = Base64.getUrlEncoder().withoutPadding()
    private val decoder = Base64.getUrlDecoder()
    private val objectMapper = ObjectMapper()

    fun createAccessToken(userId: Long, expiresAt: Instant): String =
        createToken(
            claims = baseClaims(userId, expiresAt) + ("type" to ACCESS_TYPE),
        )

    fun createRefreshToken(userId: Long, jti: UUID, expiresAt: Instant): String =
        createToken(
            claims = baseClaims(userId, expiresAt) + mapOf(
                "jti" to jti.toString(),
                "type" to REFRESH_TYPE,
            ),
        )

    fun verify(token: String): ParsedJwt =
        try {
            parseAndVerify(token)
        } catch (exception: InvalidAccessTokenException) {
            throw exception
        } catch (exception: InvalidRefreshTokenException) {
            throw exception
        } catch (exception: RuntimeException) {
            throw InvalidAccessTokenException()
        }

    private fun parseAndVerify(token: String): ParsedJwt {
        val parts = token.split(".")
        if (parts.size != 3) throw InvalidRefreshTokenException()

        verifySignature(parts)
        val claims = parseClaims(parts[1])
        validateIssuerAndAudience(claims)

        val expiresAt = Instant.ofEpochSecond((claims["exp"] as Number).toLong())
        if (!expiresAt.isAfter(clock.instant())) throw InvalidRefreshTokenException()

        return ParsedJwt(
            subject = claims["sub"] as? String ?: throw InvalidRefreshTokenException(),
            type = claims["type"] as? String ?: throw InvalidRefreshTokenException(),
            expiresAt = expiresAt,
            jti = claims["jti"] as? String,
        )
    }

    private fun baseClaims(userId: Long, expiresAt: Instant): Map<String, Any> =
        mapOf(
            "sub" to userId.toString(),
            "iss" to ISSUER,
            "aud" to AUDIENCE,
            "iat" to clock.instant().epochSecond,
            "exp" to expiresAt.epochSecond,
        )

    private fun createToken(claims: Map<String, Any>): String {
        val header = mapOf("alg" to "HS256", "typ" to "JWT")
        val encodedHeader = encoder.encodeToString(objectMapper.writeValueAsBytes(header))
        val encodedPayload = encoder.encodeToString(objectMapper.writeValueAsBytes(claims))
        val signingInput = "$encodedHeader.$encodedPayload"
        return "$signingInput.${hmacSha256(signingInput)}"
    }

    private fun verifySignature(parts: List<String>) {
        val signingInput = "${parts[0]}.${parts[1]}"
        val expectedSignature = hmacSha256(signingInput)
        if (!constantTimeEquals(expectedSignature, parts[2])) throw InvalidAccessTokenException()
    }

    private fun validateIssuerAndAudience(claims: Map<String, Any>) {
        if (claims["iss"] != ISSUER || claims["aud"] != AUDIENCE) {
            throw InvalidAccessTokenException()
        }
    }

    private fun parseClaims(encodedPayload: String): Map<String, Any> {
        val json = String(decoder.decode(encodedPayload), StandardCharsets.UTF_8)
        return objectMapper.readValue(json, object : TypeReference<Map<String, Any>>() {})
    }

    private fun hmacSha256(signingInput: String): String {
        val mac = Mac.getInstance("HmacSHA256")
        mac.init(SecretKeySpec(secret.toByteArray(StandardCharsets.UTF_8), "HmacSHA256"))
        return encoder.encodeToString(mac.doFinal(signingInput.toByteArray(StandardCharsets.UTF_8)))
    }

    private fun constantTimeEquals(expected: String, actual: String): Boolean =
        java.security.MessageDigest.isEqual(
            expected.toByteArray(StandardCharsets.UTF_8),
            actual.toByteArray(StandardCharsets.UTF_8),
        )

    companion object {
        const val ACCESS_TYPE = "access"
        const val REFRESH_TYPE = "refresh"
        private const val ISSUER = "kicklog"
        private const val AUDIENCE = "kicklog-ios"
    }
}
