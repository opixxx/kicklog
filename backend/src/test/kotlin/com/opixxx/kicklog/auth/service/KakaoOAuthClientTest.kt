package com.opixxx.kicklog.auth.service

import com.opixxx.kicklog.common.exception.ErrorCode
import com.opixxx.kicklog.common.exception.KickLogException
import com.sun.net.httpserver.HttpServer
import org.junit.jupiter.api.AfterEach
import org.junit.jupiter.api.BeforeEach
import org.springframework.http.client.SimpleClientHttpRequestFactory
import org.springframework.web.client.RestClient
import java.net.InetSocketAddress
import java.time.Duration
import java.util.concurrent.Executors
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue
import kotlin.test.assertFailsWith

/**
 * 카카오 사용자 정보 조회의 외부 호출 계약.
 *
 * 초점은 **응답하지 않는 상대에게 묶이지 않는 것**이다. `RestClient.create()` 를 쓰면
 * `HttpURLConnection` 기본 타임아웃이 0(무한)이라 호출 스레드가 영구 점유되고,
 * 동기 블로킹 모델에서는 그것이 전역 장애가 된다 (ADR-0017 D11).
 */
class KakaoOAuthClientTest {

    private lateinit var server: HttpServer

    @BeforeEach
    fun setUp() {
        server = HttpServer.create(InetSocketAddress("127.0.0.1", 0), 0)
        server.executor = Executors.newSingleThreadExecutor()
    }

    @AfterEach
    fun tearDown() {
        server.stop(0)
    }

    @Test
    fun `정상 응답은 OAuth 사용자 정보로 변환된다`() {
        server.createContext("/me") { exchange ->
            val body = """{"id":4242,"kakao_account":{"email":"kakao@example.com","profile":{"nickname":"옵식스"}}}"""
            exchange.responseHeaders.add("Content-Type", "application/json")
            exchange.sendResponseHeaders(200, body.toByteArray().size.toLong())
            exchange.responseBody.use { it.write(body.toByteArray()) }
        }
        server.start()

        val userInfo = client(readTimeoutMillis = 3_000).fetchUserInfo("kakao-access-token")

        assertEquals("4242", userInfo.providerUserId)
        assertEquals("kakao@example.com", userInfo.email)
    }

    @Test
    fun `카카오가 응답하지 않아도 무한 대기하지 않고 외부 장애로 끝난다`() {
        server.createContext("/me") { exchange ->
            Thread.sleep(5_000)
            exchange.sendResponseHeaders(200, 0)
            exchange.responseBody.close()
        }
        server.start()

        val startedAt = System.nanoTime()
        val exception = assertFailsWith<KickLogException> {
            client(readTimeoutMillis = 300).fetchUserInfo("kakao-access-token")
        }
        val elapsedMs = (System.nanoTime() - startedAt) / 1_000_000

        assertEquals(ErrorCode.EXTERNAL_KAKAO_UNAVAILABLE, exception.errorCode)
        assertTrue(elapsedMs < 3_000, "읽기 타임아웃 안에 끝나야 한다 (실제 ${elapsedMs}ms)")
    }

    @Test
    fun `카카오가 401 을 주면 카카오 토큰 오류로 변환된다`() {
        server.createContext("/me") { exchange ->
            exchange.sendResponseHeaders(401, -1)
            exchange.close()
        }
        server.start()

        val exception = assertFailsWith<KickLogException> {
            client(readTimeoutMillis = 3_000).fetchUserInfo("expired-token")
        }

        assertEquals(ErrorCode.AUTH_INVALID_KAKAO_TOKEN, exception.errorCode)
    }

    private fun client(readTimeoutMillis: Long): KakaoOAuthClient =
        KakaoOAuthClient(
            properties = KakaoProperties(userInfoUrl = "http://127.0.0.1:${server.address.port}/me"),
            restClientBuilder = RestClient.builder().requestFactory(
                SimpleClientHttpRequestFactory().apply {
                    setConnectTimeout(Duration.ofMillis(300))
                    setReadTimeout(Duration.ofMillis(readTimeoutMillis))
                },
            ),
        )
}
