package com.opixxx.kicklog.loadtest

import com.fasterxml.jackson.databind.ObjectMapper
import org.assertj.core.api.Assertions.assertThat
import org.junit.jupiter.api.AfterAll
import org.junit.jupiter.api.BeforeEach
import org.junit.jupiter.api.DisplayName
import org.junit.jupiter.api.Test
import org.springframework.beans.factory.annotation.Autowired
import org.springframework.boot.test.context.SpringBootTest
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc
import org.springframework.test.context.ActiveProfiles
import org.springframework.test.context.DynamicPropertyRegistry
import org.springframework.test.context.DynamicPropertySource
import org.springframework.test.web.servlet.MockMvc
import org.springframework.test.web.servlet.get

/**
 * W-EXT 계약 테스트 — `GET /loadtest/ext` 의 응답·검증·장애 변환.
 *
 * **Testcontainers 를 쓰지 않는다.** W-EXT 경로는 DB 를 전혀 타지 않는 것이 설계 전제이고
 * (EXEC_PLAN §1: 구속 자원을 Tomcat 스레드로 귀속시키기 위해 DB 를 배제), 그 전제를 테스트가
 * 깨면 안 된다. 다만 컨텍스트 부팅에는 DataSource 가 필요하므로 프로파일을 `loadtest,test` 로
 * 겹쳐 활성화해 application-test.yml 의 H2 를 쓴다(나중에 선언된 프로파일이 우선).
 *
 * 외부 의존은 [UpstreamStubServer] 로 **실제 HTTP** 를 세운다 — 프로덕션이 고른
 * request factory 그대로 소켓 통신을 하게 두는 것이 이 하네스 검증의 핵심이다.
 */
@SpringBootTest
@AutoConfigureMockMvc
@ActiveProfiles("loadtest", "test")
class LoadTestExternalEndpointTest {

    @Autowired
    private lateinit var mockMvc: MockMvc

    @Autowired
    private lateinit var properties: LoadTestProperties

    // DI 컨테이너의 ObjectMapper 빈은 Jackson 3(tools.jackson) 타입이라 com.fasterxml 타입으로는
    // autowire 되지 않는다. 응답 JSON 파싱 용도라 기존 테스트 컨벤션대로 직접 생성한다.
    private val objectMapper = ObjectMapper()

    @BeforeEach
    fun resetStub() {
        stub.failWithServerError = false
        stub.resetRequestCount()
    }

    @Test
    @DisplayName("Happy 1: delayMs=50 → 200, upstreamDelayMs=50, elapsedMs >= 50")
    fun `지연 50ms 를 주입하면 upstream 지연과 블로킹 시간이 응답에 담긴다`() {
        val body = mockMvc.get("/loadtest/ext") {
            param("delayMs", "50")
        }.andExpect {
            status { isOk() }
        }.andReturn().response.contentAsString

        val json = objectMapper.readTree(body)
        assertThat(json.get("upstreamDelayMs").asInt()).isEqualTo(50)
        assertThat(json.get("elapsedMs").asLong()).isGreaterThanOrEqualTo(50L)
        // 응답이 정말 stub 에서 왔는지 — 캐시·모킹이 끼어들지 않았다는 확인.
        assertThat(json.get("upstreamPid").asInt()).isEqualTo(UpstreamStubServer.STUB_PID)
        assertThat(stub.receivedRequestCount).isEqualTo(1)
    }

    @Test
    @DisplayName("Happy 2: delayMs 미지정 → default-delay-ms(200) 적용")
    fun `delayMs 를 생략하면 설정된 기본 지연이 적용된다`() {
        // 기본값이 200ms 라는 사실 자체가 측정 시나리오의 전제다(동시성 = 주입률 × 지연).
        assertThat(properties.defaultDelayMs).isEqualTo(200)

        val body = mockMvc.get("/loadtest/ext")
            .andExpect { status { isOk() } }
            .andReturn().response.contentAsString

        val json = objectMapper.readTree(body)
        assertThat(json.get("upstreamDelayMs").asInt()).isEqualTo(properties.defaultDelayMs)
        assertThat(json.get("elapsedMs").asLong())
            .isGreaterThanOrEqualTo(properties.defaultDelayMs.toLong())
    }

    @Test
    @DisplayName("Unhappy 1: upstream 500 → 502 EXTERNAL_UPSTREAM_UNAVAILABLE (스택·내부 URL 미노출)")
    fun `upstream 이 500 을 주면 502 로 변환되고 내부 정보가 노출되지 않는다`() {
        stub.failWithServerError = true

        val body = mockMvc.get("/loadtest/ext") {
            param("delayMs", "0")
        }.andExpect {
            status { isBadGateway() }
            jsonPath("$.code") { value("EXTERNAL_UPSTREAM_UNAVAILABLE") }
        }.andReturn().response.contentAsString

        // stub 은 장애 본문에 내부 URL 을 일부러 담았다 — 그게 클라이언트까지 새지 않아야 한다.
        assertThat(body).doesNotContain("localhost")
        assertThat(body).doesNotContain(stub.port.toString())
        assertThat(body).doesNotContain("internalUrl")
        assertThat(body).doesNotContain("upstream boom")
        // 스택트레이스 흔적(예외 클래스명·프레임) 미노출.
        assertThat(body).doesNotContain("Exception")
        assertThat(body).doesNotContain("com.opixxx")
        assertThat(objectMapper.readTree(body).get("message").asText())
            .isEqualTo("외부 의존 서비스가 일시적으로 응답하지 않습니다")
    }

    @Test
    @DisplayName("Unhappy 3: delayMs=-5 → 400 VALIDATION_FAILED (한글 메시지)")
    fun `음수 지연은 400 으로 거부되고 외부 호출을 하지 않는다`() {
        val body = mockMvc.get("/loadtest/ext") {
            param("delayMs", "-5")
        }.andExpect {
            status { isBadRequest() }
            jsonPath("$.code") { value("VALIDATION_FAILED") }
        }.andReturn().response.contentAsString

        val message = objectMapper.readTree(body).get("message").asText()
        assertThat(message).containsPattern("[가-힣]")
        assertThat(message).contains("delayMs")
        // 검증 실패는 외부 호출 전에 끝나야 한다 — 잘못된 요청이 upstream 을 때리면 측정이 오염된다.
        assertThat(stub.receivedRequestCount).isZero()
    }

    @Test
    @DisplayName("Edge 2: delayMs > max-delay-ms(10000) → 400 (측정 사고 방지)")
    fun `상한을 넘는 지연은 400 으로 거부된다`() {
        assertThat(properties.maxDelayMs).isEqualTo(10_000)

        mockMvc.get("/loadtest/ext") {
            param("delayMs", (properties.maxDelayMs + 1).toString())
        }.andExpect {
            status { isBadRequest() }
            jsonPath("$.code") { value("VALIDATION_FAILED") }
        }

        assertThat(stub.receivedRequestCount).isZero()
    }

    @Test
    @DisplayName("Edge 2-경계: delayMs == max-delay-ms 는 허용 (off-by-one 방지)")
    fun `상한과 같은 값은 허용된다`() {
        // 경계값까지 거부하면 측정 스크립트가 상한에서 전부 실패한다 — 경계 포함 여부를 고정한다.
        // 상한(10s) 만큼 실제로 기다리지 않도록 upstream 호출 자체는 stub 이 지연 없이 받게 둔다.
        // (검증 통과 여부만 보려면 stub 쪽 sleep 이 필요하지 않으므로 ms 파라미터는 그대로 전달된다)
        stub.failWithServerError = true

        mockMvc.get("/loadtest/ext") {
            param("delayMs", properties.maxDelayMs.toString())
        }.andExpect {
            // 검증은 통과했고(400 아님) upstream 단계까지 갔다는 것이 핵심.
            status { isBadGateway() }
            jsonPath("$.code") { value("EXTERNAL_UPSTREAM_UNAVAILABLE") }
        }

        assertThat(stub.receivedRequestCount).isEqualTo(1)
    }

    companion object {
        // @DynamicPropertySource 가 호출되려면 클래스 초기화가 먼저 일어나므로, 여기서 띄운 stub 의
        // 포트를 안전하게 프로퍼티로 넘길 수 있다.
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
