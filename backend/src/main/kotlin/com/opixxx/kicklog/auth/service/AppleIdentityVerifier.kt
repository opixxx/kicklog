package com.opixxx.kicklog.auth.service

import com.fasterxml.jackson.core.JsonProcessingException
import com.fasterxml.jackson.databind.JsonNode
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
import java.time.Clock
import java.time.Instant
import java.time.temporal.ChronoUnit
import java.util.Base64
import java.util.concurrent.atomic.AtomicReference

@ConfigurationProperties(prefix = "kicklog.apple")
data class AppleProperties(
    val clientId: String,
    val jwksUrl: String,
    /**
     * JWKS 캐시 수명. Apple 의 서명 키는 로테이션 주기가 길어 매 로그인마다 받아올 이유가 없다.
     * 짧게 잡으면 캐시의 의미가 없고, 길게 잡아도 **kid 미스 시 즉시 재조회**하므로
     * 로테이션에 뒤처지지 않는다 (fetchPublicKey 참조).
     */
    val jwksCacheTtlMinutes: Long = 360,
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
    // 공유 빌더를 쓴다 — RestClient.create() 는 타임아웃이 없어 무한 대기한다 (RestClientConfig 참조).
    restClientBuilder: RestClient.Builder,
    private val clock: Clock,
) {
    private val restClient = restClientBuilder.build()
    private val decoder = Base64.getUrlDecoder()
    private val objectMapper = ObjectMapper()

    /**
     * JWKS 캐시. 매 로그인마다 Apple 을 호출하던 것을 없앤다 — 외부 호출이 줄면
     * 외부 장애에 대한 노출도 함께 줄어든다.
     *
     * 단일 인스턴스 운영(ADR-0016)이라 프로세스 내 캐시로 충분하다. 경쟁 조건이 생겨도
     * 중복 조회 한 번이 전부고 결과는 같으므로 락을 걸지 않는다.
     */
    private val cachedJwks = AtomicReference<CachedJwks?>(null)

    private data class CachedJwks(
        val keysByKid: Map<String, RSAPublicKey>,
        val fetchedAt: Instant,
    )

    fun verify(identityToken: String): OAuthUserInfo {
        val parts = identityToken.split(".")
        if (parts.size != 3) {
            throw KickLogException(ErrorCode.AUTH_INVALID_APPLE_TOKEN)
        }

        val header = decodeHeader(parts[0])
        val payload = decodePayload(parts[1])
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

    /**
     * kid 에 해당하는 공개키를 돌려준다. 캐시를 먼저 보고, 없으면 한 번만 재조회한다.
     *
     * **캐시가 신선해도 kid 가 없으면 재조회하는 것이 핵심이다.** Apple 이 키를 로테이션한 직후
     * 새 kid 로 서명된 토큰이 들어오는데 TTL 만 믿고 캐시를 쓰면, 남은 TTL 동안 **모든 로그인이 실패**한다.
     * 반대로 재조회는 **한 번만** 한다 — 없는 kid 를 들고 온 토큰(위조·오설정)이 매번 Apple 을
     * 때리게 두면 그 자체가 증폭 경로가 된다.
     */
    private fun fetchPublicKey(kid: String): RSAPublicKey {
        cachedJwks.get()
            ?.takeIf { Instant.now(clock).isBefore(it.fetchedAt.plus(properties.jwksCacheTtlMinutes, ChronoUnit.MINUTES)) }
            ?.keysByKid?.get(kid)
            ?.let { return it }

        return refreshJwks()[kid] ?: throw KickLogException(ErrorCode.AUTH_INVALID_APPLE_TOKEN)
    }

    private fun refreshJwks(): Map<String, RSAPublicKey> {
        val jwks = try {
            restClient.get()
                .uri(properties.jwksUrl)
                .retrieve()
                .body(AppleJwksResponse::class.java)
        } catch (exception: RestClientException) {
            throw KickLogException(ErrorCode.EXTERNAL_APPLE_UNAVAILABLE, cause = exception)
        } ?: throw KickLogException(ErrorCode.EXTERNAL_APPLE_UNAVAILABLE)

        val keysByKid = jwks.keys
            .filter { it.kty == "RSA" }
            .associate { it.kid to it.toPublicKey() }

        cachedJwks.set(CachedJwks(keysByKid = keysByKid, fetchedAt = Instant.now(clock)))
        return keysByKid
    }

    private fun AppleJwk.toPublicKey(): RSAPublicKey {
        val modulus = BigInteger(1, decoder.decode(n))
        val exponent = BigInteger(1, decoder.decode(e))
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

    private fun decodeHeader(value: String): AppleJwtHeader {
        val json = decodeJson(value)
        return AppleJwtHeader(
            kid = json.textOrNull("kid"),
            alg = json.textOrNull("alg"),
        )
    }

    private fun decodePayload(value: String): AppleJwtPayload {
        val json = decodeJson(value)
        return AppleJwtPayload(
            sub = json.textOrNull("sub"),
            email = json.textOrNull("email"),
            iss = json.textOrNull("iss"),
            aud = json.textOrNull("aud"),
            exp = json.longOrNull("exp"),
        )
    }

    private fun decodeJson(value: String): JsonNode {
        return try {
            objectMapper.readTree(decoder.decode(value))
        } catch (exception: IllegalArgumentException) {
            throw KickLogException(ErrorCode.AUTH_INVALID_APPLE_TOKEN, cause = exception)
        } catch (exception: JsonProcessingException) {
            throw KickLogException(ErrorCode.AUTH_INVALID_APPLE_TOKEN, cause = exception)
        }
    }

    private fun JsonNode.textOrNull(fieldName: String): String? {
        val field = get(fieldName)?.takeUnless { it.isNull } ?: return null
        return if (field.isTextual) field.asText() else null
    }

    private fun JsonNode.longOrNull(fieldName: String): Long? {
        val field = get(fieldName)?.takeUnless { it.isNull } ?: return null
        return if (field.isNumber) field.asLong() else null
    }
}
