package com.opixxx.kicklog.auth.service

import com.opixxx.kicklog.common.exception.ErrorCode
import com.opixxx.kicklog.common.exception.KickLogException
import com.sun.net.httpserver.HttpServer
import org.junit.jupiter.api.AfterEach
import org.junit.jupiter.api.BeforeEach
import org.springframework.http.client.SimpleClientHttpRequestFactory
import org.springframework.web.client.RestClient
import java.math.BigInteger
import java.net.InetSocketAddress
import java.security.KeyPair
import java.security.KeyPairGenerator
import java.security.Signature
import java.security.interfaces.RSAPublicKey
import java.time.Clock
import java.time.Duration
import java.time.Instant
import java.time.ZoneId
import java.time.ZoneOffset
import java.util.Base64
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicInteger
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertTrue

class AppleIdentityVerifierTest {

    private lateinit var keyPair: KeyPair
    private lateinit var jwksServer: HttpServer
    private lateinit var verifier: AppleIdentityVerifier

    /** 현재 JWKS 가 내려주는 키 목록. 로테이션을 흉내 내려고 테스트 중에 갈아끼운다. */
    private lateinit var servedKeys: List<Pair<String, RSAPublicKey>>

    /** JWKS 조회 횟수 — 캐시가 실제로 호출을 줄였는지 확인할 유일한 방법이다. */
    private val jwksRequestCount = AtomicInteger(0)

    /** 캐시 TTL 만료를 재현하려면 시간을 통제해야 한다. */
    private var currentTime: Instant = Instant.parse("2026-10-31T00:00:00Z")
    private val fixedClock = object : Clock() {
        override fun getZone(): ZoneId = ZoneOffset.UTC
        override fun withZone(zone: ZoneId?): Clock = this
        override fun instant(): Instant = currentTime
    }

    @BeforeEach
    fun setUp() {
        keyPair = newKeyPair()
        servedKeys = listOf("test-kid" to (keyPair.public as RSAPublicKey))

        jwksServer = HttpServer.create(InetSocketAddress("127.0.0.1", 0), 0)
        jwksServer.createContext("/keys") { exchange ->
            jwksRequestCount.incrementAndGet()
            val body = jwksResponse(servedKeys)
            exchange.responseHeaders.add("Content-Type", "application/json")
            exchange.sendResponseHeaders(200, body.toByteArray().size.toLong())
            exchange.responseBody.use { it.write(body.toByteArray()) }
        }
        jwksServer.start()

        verifier = AppleIdentityVerifier(
            properties = AppleProperties(
                clientId = "com.opixxx.kicklog",
                jwksUrl = "http://127.0.0.1:${jwksServer.address.port}/keys",
                jwksCacheTtlMinutes = 360,
            ),
            restClientBuilder = RestClient.builder(),
            clock = fixedClock,
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

    // ── JWKS 캐시 ────────────────────────────────────────────────────────────

    @Test
    fun `같은 kid 로 여러 번 검증해도 JWKS 는 한 번만 조회한다`() {
        val token = appleJwt("apple-user-1", "apple@example.com", Instant.now().plusSeconds(300))

        repeat(3) { verifier.verify(token) }

        // 캐시 이전에는 로그인마다 Apple 을 때렸다. 이 단언이 깨지면 캐시가 사라진 것이다.
        assertEquals(1, jwksRequestCount.get())
    }

    @Test
    fun `캐시가 신선해도 kid 가 없으면 재조회한다`() {
        // 로테이션 시나리오: 첫 로그인으로 캐시를 채운 뒤 Apple 이 키를 갈아끼운다.
        verifier.verify(appleJwt("apple-user-1", "apple@example.com", Instant.now().plusSeconds(300)))
        assertEquals(1, jwksRequestCount.get())

        val rotated = newKeyPair()
        keyPair = rotated
        servedKeys = listOf("rotated-kid" to (rotated.public as RSAPublicKey))

        val token = appleJwt(
            subject = "apple-user-2",
            email = "rotated@example.com",
            expiration = Instant.now().plusSeconds(300),
            kid = "rotated-kid",
        )
        val userInfo = verifier.verify(token)

        // TTL 만 믿고 캐시를 썼다면 남은 TTL 동안 모든 로그인이 실패했을 것이다.
        assertEquals("apple-user-2", userInfo.providerUserId)
        assertEquals(2, jwksRequestCount.get())
    }

    @Test
    fun `재조회 후에도 kid 가 없으면 조회를 반복하지 않고 토큰 오류로 끝낸다`() {
        verifier.verify(appleJwt("apple-user-1", "apple@example.com", Instant.now().plusSeconds(300)))
        assertEquals(1, jwksRequestCount.get())

        // 서버에 없는 kid 로 서명된 토큰 — 위조이거나 설정이 어긋난 경우다.
        val unknown = appleJwt(
            subject = "apple-user-3",
            email = "x@example.com",
            expiration = Instant.now().plusSeconds(300),
            kid = "unknown-kid",
        )

        val exception = assertFailsWith<KickLogException> { verifier.verify(unknown) }

        assertEquals(ErrorCode.AUTH_INVALID_APPLE_TOKEN, exception.errorCode)
        // 재조회는 정확히 1회. 무한 재시도를 두면 위조 토큰이 Apple 을 때리는 증폭 경로가 된다.
        assertEquals(2, jwksRequestCount.get())
    }

    @Test
    fun `TTL 이 지나면 kid 가 캐시에 있어도 다시 조회한다`() {
        val token = appleJwt("apple-user-1", "apple@example.com", Instant.now().plusSeconds(300))
        verifier.verify(token)
        assertEquals(1, jwksRequestCount.get())

        currentTime = currentTime.plus(Duration.ofMinutes(361))
        verifier.verify(token)

        assertEquals(2, jwksRequestCount.get())
    }

    // ── 타임아웃 (회귀 방지) ─────────────────────────────────────────────────

    @Test
    fun `JWKS 가 응답하지 않아도 무한 대기하지 않고 외부 장애로 끝난다`() {
        // RestClient.create() 를 쓰면 HttpURLConnection 기본값이 0(무한)이라 이 테스트가 멈춘다.
        // 스레드 영구 점유 → 전역 장애로 번지는 경로의 회귀 방지다 (ADR-0017 D11).
        val hangingServer = HttpServer.create(InetSocketAddress("127.0.0.1", 0), 0)
        hangingServer.createContext("/keys") { exchange ->
            Thread.sleep(5_000)
            exchange.sendResponseHeaders(200, 0)
            exchange.responseBody.close()
        }
        hangingServer.executor = Executors.newSingleThreadExecutor()
        hangingServer.start()

        val slowVerifier = AppleIdentityVerifier(
            properties = AppleProperties(
                clientId = "com.opixxx.kicklog",
                jwksUrl = "http://127.0.0.1:${hangingServer.address.port}/keys",
            ),
            restClientBuilder = RestClient.builder().requestFactory(
                SimpleClientHttpRequestFactory().apply {
                    setConnectTimeout(Duration.ofMillis(300))
                    setReadTimeout(Duration.ofMillis(300))
                },
            ),
            clock = fixedClock,
        )

        try {
            val token = appleJwt("apple-user-1", "apple@example.com", Instant.now().plusSeconds(300))
            val startedAt = System.nanoTime()

            val exception = assertFailsWith<KickLogException> { slowVerifier.verify(token) }

            val elapsedMs = (System.nanoTime() - startedAt) / 1_000_000
            assertEquals(ErrorCode.EXTERNAL_APPLE_UNAVAILABLE, exception.errorCode)
            assertTrue(elapsedMs < 3_000, "읽기 타임아웃 안에 끝나야 한다 (실제 ${elapsedMs}ms)")
        } finally {
            hangingServer.stop(0)
        }
    }

    // ── 헬퍼 ────────────────────────────────────────────────────────────────

    private fun newKeyPair(): KeyPair =
        KeyPairGenerator.getInstance("RSA").apply { initialize(2048) }.generateKeyPair()

    private fun appleJwt(
        subject: String,
        email: String,
        expiration: Instant,
        kid: String = "test-kid",
    ): String {
        val header = """{"kid":"$kid","alg":"RS256"}"""
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

    private fun jwksResponse(keys: List<Pair<String, RSAPublicKey>>): String {
        val entries = keys.joinToString(",") { (kid, publicKey) ->
            """
                {
                  "kid": "$kid",
                  "kty": "RSA",
                  "alg": "RS256",
                  "n": "${base64Url(unsignedBytes(publicKey.modulus))}",
                  "e": "${base64Url(unsignedBytes(publicKey.publicExponent))}"
                }
            """.trimIndent()
        }
        return """{ "keys": [ $entries ] }"""
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
