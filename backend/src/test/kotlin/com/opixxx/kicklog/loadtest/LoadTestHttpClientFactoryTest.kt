package com.opixxx.kicklog.loadtest

import org.assertj.core.api.Assertions.assertThat
import org.assertj.core.api.Assertions.fail
import org.junit.jupiter.api.AfterAll
import org.junit.jupiter.api.DisplayName
import org.junit.jupiter.api.Test
import org.springframework.beans.factory.annotation.Autowired
import org.springframework.beans.factory.annotation.Qualifier
import org.springframework.boot.test.context.SpringBootTest
import org.springframework.http.client.ClientHttpRequestFactory
import org.springframework.http.client.JdkClientHttpRequestFactory
import org.springframework.http.client.SimpleClientHttpRequestFactory
import org.springframework.test.context.ActiveProfiles
import org.springframework.test.context.DynamicPropertyRegistry
import org.springframework.test.context.DynamicPropertySource
import org.springframework.web.client.RestClient

/**
 * RestClient 가 들고 있는 [ClientHttpRequestFactory] 를 꺼낸다.
 *
 * 측정의 전제가 "같은 바이너리에서 프로퍼티만 바꿔 커넥션 형상을 교체한다"이므로, 프로퍼티가
 * 실제로 팩토리 선택까지 전달됐는지는 **빈을 직접 들여다보는 것 말고는 확인할 길이 없다**.
 * 프로덕션 코드의 가시성을 테스트 때문에 넓히지 않기 위해 테스트 쪽 리플렉션을 택했다.
 * Spring 내부 필드명이 바뀌면 이 테스트가 명시적으로 실패한다(조용히 통과하지 않는다).
 */
private fun requestFactoryOf(restClient: RestClient): ClientHttpRequestFactory {
    var type: Class<*>? = restClient.javaClass
    while (type != null) {
        val field = type.declaredFields.firstOrNull {
            ClientHttpRequestFactory::class.java.isAssignableFrom(it.type) && it.name == "clientRequestFactory"
        }
        if (field != null) {
            field.isAccessible = true
            return field.get(restClient) as ClientHttpRequestFactory
        }
        type = type.superclass
    }
    return fail("RestClient(${restClient.javaClass.name}) 에서 clientRequestFactory 필드를 찾지 못했다 — Spring 내부 구조 변경 가능성")
}

/**
 * Happy 3 — `kicklog.loadtest.http-client=simple` 이면 커넥션 풀이 없는
 * [SimpleClientHttpRequestFactory] 가 주입된다. 이게 **운영 인증 경로와 같은 형상**이고,
 * 기준선이 운영을 대변해야 측정 결과를 운영에 귀속할 수 있다 (EXEC_PLAN §2-2 규칙 2).
 */
@SpringBootTest(
    classes = [LoadTestHttpClientConfig::class, LoadTestUpstreamClient::class],
    webEnvironment = SpringBootTest.WebEnvironment.NONE,
    properties = ["kicklog.loadtest.http-client=simple"],
)
@ActiveProfiles("loadtest")
class LoadTestSimpleHttpClientTest {

    @Autowired
    @Qualifier("loadTestUpstreamRestClient")
    private lateinit var restClient: RestClient

    @Autowired
    private lateinit var upstreamClient: LoadTestUpstreamClient

    @Test
    @DisplayName("Happy 3: http-client=simple → SimpleClientHttpRequestFactory 주입")
    fun `simple 은 커넥션 풀 없는 팩토리를 쓴다`() {
        val factory = requestFactoryOf(restClient)

        assertThat(factory).isInstanceOf(SimpleClientHttpRequestFactory::class.java)
        assertThat(factory).isNotInstanceOf(JdkClientHttpRequestFactory::class.java)
    }

    @Test
    @DisplayName("기본값 고정: 프로퍼티 미지정 시 형상은 SIMPLE(운영 형상)")
    fun `프로퍼티 기본값은 simple 이다`() {
        // 기본값이 바뀌면 기준선이 "운영 형상"이 아니게 되어 측정의 의미가 달라진다.
        assertThat(LoadTestProperties().httpClient).isEqualTo(LoadTestProperties.HttpClientKind.SIMPLE)
    }

    @Test
    @DisplayName("선택된 팩토리로 실제 호출이 동작한다")
    fun `simple 형상으로도 upstream 호출이 성공한다`() {
        val echo = upstreamClient.fetchWithDelay(10)

        assertThat(echo.delayedMs).isEqualTo(10)
        assertThat(echo.pid).isEqualTo(UpstreamStubServer.STUB_PID)
    }

    companion object {
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

/**
 * Happy 4 — `kicklog.loadtest.http-client=pooled` 이면 커넥션 풀을 가진
 * [JdkClientHttpRequestFactory] 로 교체된다. 두 형상을 같은 바이너리에서 비교해야
 * 처리량 차이를 "커넥션 관리"에 귀속할 수 있다.
 */
@SpringBootTest(
    classes = [LoadTestHttpClientConfig::class, LoadTestUpstreamClient::class],
    webEnvironment = SpringBootTest.WebEnvironment.NONE,
    properties = ["kicklog.loadtest.http-client=pooled"],
)
@ActiveProfiles("loadtest")
class LoadTestPooledHttpClientTest {

    @Autowired
    @Qualifier("loadTestUpstreamRestClient")
    private lateinit var restClient: RestClient

    @Autowired
    private lateinit var upstreamClient: LoadTestUpstreamClient

    @Test
    @DisplayName("Happy 4: http-client=pooled → JdkClientHttpRequestFactory 주입")
    fun `pooled 는 커넥션 풀을 가진 팩토리를 쓴다`() {
        val factory = requestFactoryOf(restClient)

        assertThat(factory).isInstanceOf(JdkClientHttpRequestFactory::class.java)
        assertThat(factory).isNotInstanceOf(SimpleClientHttpRequestFactory::class.java)
    }

    @Test
    @DisplayName("선택된 팩토리로 실제 호출이 동작한다")
    fun `pooled 형상으로도 upstream 호출이 성공한다`() {
        // 노브를 바꿨을 때 호출 자체가 깨지면 비교 측정이 아예 불가능하다.
        val echo = upstreamClient.fetchWithDelay(10)

        assertThat(echo.delayedMs).isEqualTo(10)
        assertThat(echo.pid).isEqualTo(UpstreamStubServer.STUB_PID)
    }

    companion object {
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
