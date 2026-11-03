package com.opixxx.kicklog.loadtest

import com.opixxx.kicklog.common.exception.ErrorCode
import com.opixxx.kicklog.common.exception.KickLogException
import org.assertj.core.api.Assertions.assertThat
import org.junit.jupiter.api.AfterAll
import org.junit.jupiter.api.DisplayName
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.assertThrows
import org.springframework.beans.factory.annotation.Autowired
import org.springframework.boot.test.context.SpringBootTest
import org.springframework.test.context.ActiveProfiles
import org.springframework.test.context.DynamicPropertyRegistry
import org.springframework.test.context.DynamicPropertySource

/**
 * Unhappy 2 — upstream 미기동(connection refused) 시 [ErrorCode.EXTERNAL_UPSTREAM_UNAVAILABLE] 로
 * 변환되고, 호출이 **무한 대기하지 않는다**.
 *
 * 컨텍스트는 W-EXT 에 필요한 두 빈만 올린다(웹·DB 없음). 외부 호출 실패의 변환 책임은
 * [LoadTestUpstreamClient] 에 있으므로 MVC 를 통과시킬 필요가 없고, 타임아웃 프로퍼티가 다르면
 * 어차피 별도 컨텍스트가 되므로 가볍게 두는 쪽이 낫다.
 */
@SpringBootTest(
    classes = [LoadTestHttpClientConfig::class, LoadTestUpstreamClient::class],
    webEnvironment = SpringBootTest.WebEnvironment.NONE,
    properties = [
        "kicklog.loadtest.connect-timeout-millis=300",
        "kicklog.loadtest.read-timeout-millis=300",
    ],
)
@ActiveProfiles("loadtest")
class LoadTestUpstreamDownTest {

    @Autowired
    private lateinit var upstreamClient: LoadTestUpstreamClient

    @Test
    @DisplayName("upstream 미기동 → EXTERNAL_UPSTREAM_UNAVAILABLE, 무한 대기 없음")
    fun `연결이 거부되면 외부 의존 장애로 변환된다`() {
        val startedAt = System.nanoTime()

        val exception = assertThrows<KickLogException> { upstreamClient.fetchWithDelay(10) }
        assertThat(exception.errorCode).isEqualTo(ErrorCode.EXTERNAL_UPSTREAM_UNAVAILABLE)

        val elapsedMs = (System.nanoTime() - startedAt) / 1_000_000
        // connect timeout 300ms 가 실제로 걸려 있다는 확인 — 미설정이면 OS 기본값(수십 초)까지 매달린다.
        assertThat(elapsedMs).isLessThan(5_000L)
    }

    companion object {
        private val closedPort = UpstreamStubServer.pickClosedPort()

        @DynamicPropertySource
        @JvmStatic
        fun upstream(registry: DynamicPropertyRegistry) {
            registry.add("kicklog.loadtest.upstream-base-url") { "http://localhost:$closedPort" }
        }
    }
}

/**
 * Unhappy 2 (짝) — upstream 이 응답을 늦게 주는 경우에도 read timeout 으로 끊고
 * [ErrorCode.EXTERNAL_UPSTREAM_UNAVAILABLE] 로 변환한다.
 *
 * 커넥션은 열리지만 응답이 오지 않는 상황이 운영에서 더 위험하다 — 스레드가 점유된 채로
 * 남으면 Tomcat 스레드 풀이 복구 없이 고갈된다. read timeout 이 걸려 있는지가 그 방어선이다.
 */
@SpringBootTest(
    classes = [LoadTestHttpClientConfig::class, LoadTestUpstreamClient::class],
    webEnvironment = SpringBootTest.WebEnvironment.NONE,
    properties = [
        "kicklog.loadtest.connect-timeout-millis=300",
        "kicklog.loadtest.read-timeout-millis=300",
    ],
)
@ActiveProfiles("loadtest")
class LoadTestUpstreamReadTimeoutTest {

    @Autowired
    private lateinit var upstreamClient: LoadTestUpstreamClient

    @Test
    @DisplayName("upstream 응답 지연이 read timeout 을 넘으면 EXTERNAL_UPSTREAM_UNAVAILABLE")
    fun `읽기 타임아웃이 걸리면 외부 의존 장애로 변환된다`() {
        val startedAt = System.nanoTime()

        val exception = assertThrows<KickLogException> { upstreamClient.fetchWithDelay(UPSTREAM_DELAY_MS) }
        assertThat(exception.errorCode).isEqualTo(ErrorCode.EXTERNAL_UPSTREAM_UNAVAILABLE)

        val elapsedMs = (System.nanoTime() - startedAt) / 1_000_000
        // stub 은 3초 뒤에 응답하지만 read timeout 300ms 에서 끊겨야 한다 — 10배 여유로 판정.
        assertThat(elapsedMs).isLessThan(UPSTREAM_DELAY_MS.toLong())
    }

    companion object {
        private const val UPSTREAM_DELAY_MS = 3_000

        private val stub: UpstreamStubServer = UpstreamStubServer.start()

        @DynamicPropertySource
        @JvmStatic
        fun upstream(registry: DynamicPropertyRegistry) {
            registry.add("kicklog.loadtest.upstream-base-url") { stub.baseUrl }
        }

        @AfterAll
        @JvmStatic
        fun stopStub() {
            stub.stop()
        }
    }
}
