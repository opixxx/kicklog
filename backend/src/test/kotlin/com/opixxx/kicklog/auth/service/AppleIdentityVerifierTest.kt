package com.opixxx.kicklog.auth.service

import com.opixxx.kicklog.common.exception.ErrorCode
import com.opixxx.kicklog.common.exception.KickLogException
import com.sun.net.httpserver.HttpServer
import org.junit.jupiter.api.AfterEach
import org.junit.jupiter.api.BeforeEach
import java.math.BigInteger
import java.net.InetSocketAddress
import java.security.KeyPair
import java.security.KeyPairGenerator
import java.security.Signature
import java.security.interfaces.RSAPublicKey
import java.time.Instant
import java.util.Base64
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith

class AppleIdentityVerifierTest {

    private lateinit var keyPair: KeyPair
    private lateinit var jwksServer: HttpServer
    private lateinit var verifier: AppleIdentityVerifier

    @BeforeEach
    fun setUp() {
        keyPair = KeyPairGenerator.getInstance("RSA").apply {
            initialize(2048)
        }.generateKeyPair()
        jwksServer = HttpServer.create(InetSocketAddress("127.0.0.1", 0), 0)
        jwksServer.createContext("/keys") { exchange ->
            val body = jwksResponse((keyPair.public as RSAPublicKey))
            exchange.responseHeaders.add("Content-Type", "application/json")
            exchange.sendResponseHeaders(200, body.toByteArray().size.toLong())
            exchange.responseBody.use { it.write(body.toByteArray()) }
        }
        jwksServer.start()
        verifier = AppleIdentityVerifier(
            properties = AppleProperties(
                clientId = "com.opixxx.kicklog",
                jwksUrl = "http://127.0.0.1:${jwksServer.address.port}/keys",
            ),
        )
    }

    @AfterEach
    fun tearDown() {
        jwksServer.stop(0)
    }

    @Test
    fun `유효한 Apple JWT는 OAuth 사용자 정보로 변환된다`() {
        val token = appleJwt(
            subject = "apple-user-1",
            email = "apple@example.com",
            expiration = Instant.now().plusSeconds(300),
        )

        val userInfo = verifier.verify(token)

        assertEquals("apple-user-1", userInfo.providerUserId)
        assertEquals("apple@example.com", userInfo.email)
    }

    @Test
    fun `JWT 조각 수가 3개가 아니면 Apple 토큰 오류를 반환한다`() {
        val exception = assertFailsWith<KickLogException> {
            verifier.verify("not-a-jwt")
        }

        assertEquals(ErrorCode.AUTH_INVALID_APPLE_TOKEN, exception.errorCode)
    }

    @Test
    fun `만료된 Apple JWT는 Apple 토큰 오류를 반환한다`() {
        val token = appleJwt(
            subject = "apple-user-1",
            email = "apple@example.com",
            expiration = Instant.now().minusSeconds(60),
        )

        val exception = assertFailsWith<KickLogException> {
            verifier.verify(token)
        }

        assertEquals(ErrorCode.AUTH_INVALID_APPLE_TOKEN, exception.errorCode)
    }

    private fun appleJwt(
        subject: String,
        email: String,
        expiration: Instant,
    ): String {
        val header = """{"kid":"test-kid","alg":"RS256"}"""
        val payload = """
            {
              "sub": "$subject",
              "email": "$email",
              "iss": "https://appleid.apple.com",
              "aud": "com.opixxx.kicklog",
              "exp": ${expiration.epochSecond}
            }
        """.trimIndent()
        val unsignedToken = "${base64Url(header.toByteArray())}.${base64Url(payload.toByteArray())}"
        return "$unsignedToken.${base64Url(sign(unsignedToken))}"
    }

    private fun sign(unsignedToken: String): ByteArray {
        return Signature.getInstance("SHA256withRSA").run {
            initSign(keyPair.private)
            update(unsignedToken.toByteArray())
            sign()
        }
    }

    private fun jwksResponse(publicKey: RSAPublicKey): String {
        return """
            {
              "keys": [
                {
                  "kid": "test-kid",
                  "kty": "RSA",
                  "alg": "RS256",
                  "n": "${base64Url(unsignedBytes(publicKey.modulus))}",
                  "e": "${base64Url(unsignedBytes(publicKey.publicExponent))}"
                }
              ]
            }
        """.trimIndent()
    }

    private fun unsignedBytes(value: BigInteger): ByteArray {
        val bytes = value.toByteArray()
        return if (bytes.size > 1 && bytes.first() == 0.toByte()) {
            bytes.copyOfRange(1, bytes.size)
        } else {
            bytes
        }
    }

    private fun base64Url(bytes: ByteArray): String {
        return Base64.getUrlEncoder().withoutPadding().encodeToString(bytes)
    }
}
