package com.opixxx.kicklog.auth.service

import com.fasterxml.jackson.annotation.JsonProperty
import com.fasterxml.jackson.databind.ObjectMapper
import com.opixxx.kicklog.common.exception.ErrorCode
import com.opixxx.kicklog.common.exception.KickLogException
import org.springframework.boot.context.properties.ConfigurationProperties
import org.springframework.boot.context.properties.EnableConfigurationProperties
import org.springframework.stereotype.Component
import org.springframework.web.client.RestClient
import org.springframework.web.client.RestClientException
import java.math.BigInteger
import java.security.KeyFactory
import java.security.Signature
import java.security.interfaces.RSAPublicKey
import java.security.spec.RSAPublicKeySpec
import java.time.Instant
import java.util.Base64

@ConfigurationProperties(prefix = "kicklog.apple")
data class AppleProperties(
    val clientId: String,
    val jwksUrl: String,
)

data class AppleJwksResponse(
    val keys: List<AppleJwk>,
)

data class AppleJwk(
    val kid: String,
    val kty: String,
    val alg: String,
    val n: String,
    val e: String,
)

private data class AppleJwtHeader(
    val kid: String?,
    val alg: String?,
)

private data class AppleJwtPayload(
    val sub: String?,
    val email: String?,
    val iss: String?,
    val aud: String?,
    val exp: Long?,
)

@Component
@EnableConfigurationProperties(AppleProperties::class)
class AppleIdentityVerifier(
    private val properties: AppleProperties,
) {
    private val restClient = RestClient.create()
    private val decoder = Base64.getUrlDecoder()
    private val objectMapper = ObjectMapper()

    fun verify(identityToken: String): OAuthUserInfo {
        val parts = identityToken.split(".")
        if (parts.size != 3) {
            throw KickLogException(ErrorCode.AUTH_INVALID_APPLE_TOKEN)
        }

        val header = decode(parts[0], AppleJwtHeader::class.java)
        val payload = decode(parts[1], AppleJwtPayload::class.java)
        if (header.alg != "RS256" || payload.iss != "https://appleid.apple.com" || payload.aud != properties.clientId) {
            throw KickLogException(ErrorCode.AUTH_INVALID_APPLE_TOKEN)
        }
        if (payload.exp == null || Instant.ofEpochSecond(payload.exp).isBefore(Instant.now())) {
            throw KickLogException(ErrorCode.AUTH_INVALID_APPLE_TOKEN)
        }

        val publicKey = fetchPublicKey(header.kid ?: throw KickLogException(ErrorCode.AUTH_INVALID_APPLE_TOKEN))
        verifySignature("${parts[0]}.${parts[1]}", parts[2], publicKey)

        return OAuthUserInfo(
            providerUserId = payload.sub ?: throw KickLogException(ErrorCode.AUTH_INVALID_APPLE_TOKEN),
            email = payload.email,
            displayName = null,
        )
    }

    private fun fetchPublicKey(kid: String): RSAPublicKey {
        val jwks = try {
            restClient.get()
                .uri(properties.jwksUrl)
                .retrieve()
                .body(AppleJwksResponse::class.java)
        } catch (exception: RestClientException) {
            throw KickLogException(ErrorCode.EXTERNAL_APPLE_UNAVAILABLE, cause = exception)
        } ?: throw KickLogException(ErrorCode.EXTERNAL_APPLE_UNAVAILABLE)

        val key = jwks.keys.firstOrNull { it.kid == kid && it.kty == "RSA" }
            ?: throw KickLogException(ErrorCode.AUTH_INVALID_APPLE_TOKEN)
        val modulus = BigInteger(1, decoder.decode(key.n))
        val exponent = BigInteger(1, decoder.decode(key.e))
        return KeyFactory.getInstance("RSA")
            .generatePublic(RSAPublicKeySpec(modulus, exponent)) as RSAPublicKey
    }

    private fun verifySignature(unsignedToken: String, signaturePart: String, publicKey: RSAPublicKey) {
        val signature = Signature.getInstance("SHA256withRSA")
        signature.initVerify(publicKey)
        signature.update(unsignedToken.toByteArray(Charsets.UTF_8))
        if (!signature.verify(decoder.decode(signaturePart))) {
            throw KickLogException(ErrorCode.AUTH_INVALID_APPLE_TOKEN)
        }
    }

    private fun <T> decode(value: String, type: Class<T>): T {
        return objectMapper.readValue(decoder.decode(value), type)
    }
}
