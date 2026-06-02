package com.opixxx.kicklog.loadtest

import com.fasterxml.jackson.databind.ObjectMapper
import com.opixxx.kicklog.common.security.JwtTokenProvider
import org.assertj.core.api.Assertions.assertThat
import org.junit.jupiter.api.Test
import org.springframework.beans.factory.annotation.Autowired
import org.springframework.boot.test.context.SpringBootTest
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc
import org.springframework.test.context.ActiveProfiles
import org.springframework.test.web.servlet.MockMvc
import org.springframework.test.web.servlet.get

/**
 * (3-B) /loadtest/token 통합 — 발급 토큰이 JwtTokenProvider.verifyAccessToken 를 통과하고
 * claims.userId 가 요청한 userId 와 일치하는지 검증.
 *
 * RED 단계: /loadtest/token 라우트와 LoadTestTokenResponse 가 아직 없어 실패해야 정상.
 */
@SpringBootTest
@AutoConfigureMockMvc
@ActiveProfiles("loadtest")
class LoadTestTokenIntegrationTest : LoadTestPostgresSupport() {

    @Autowired
    private lateinit var mockMvc: MockMvc

    @Autowired
    private lateinit var jwtTokenProvider: JwtTokenProvider

    // DI 컨테이너의 ObjectMapper 빈은 Jackson 3(tools.jackson) 타입이라 com.fasterxml 타입으로는
    // autowire 되지 않는다. 응답 JSON 파싱용이므로 기존 테스트 컨벤션대로 직접 생성한다.
    private val objectMapper = ObjectMapper()

    @Test
    fun `발급된 토큰은 verifyAccessToken 을 통과하고 claims userId 가 요청 userId 와 일치한다`() {
        val requestedUserId = 4242L

        val body = mockMvc.get("/loadtest/token") {
            param("userId", requestedUserId.toString())
        }.andExpect {
            status { isOk() }
            jsonPath("$.accessToken") { exists() }
        }.andReturn().response.contentAsString

        val accessToken = objectMapper.readTree(body).get("accessToken").asText()
        assertThat(accessToken).isNotBlank()

        val claims = jwtTokenProvider.verifyAccessToken(accessToken)
        assertThat(claims.userId).isEqualTo(requestedUserId)
    }
}
