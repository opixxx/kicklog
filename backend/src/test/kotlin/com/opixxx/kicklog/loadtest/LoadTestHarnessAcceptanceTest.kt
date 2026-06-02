package com.opixxx.kicklog.loadtest

import com.fasterxml.jackson.databind.ObjectMapper
import com.opixxx.kicklog.common.security.JwtTokenProvider
import org.junit.jupiter.api.Test
import org.springframework.beans.factory.annotation.Autowired
import org.springframework.boot.test.context.SpringBootTest
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc
import org.springframework.http.MediaType
import org.springframework.test.context.ActiveProfiles
import org.springframework.test.web.servlet.MockMvc
import org.springframework.test.web.servlet.get
import org.springframework.test.web.servlet.post

/**
 * (3-A) 인수 시나리오 — 부하테스트 하네스 (loadtest 프로파일 전용).
 *
 * 기존 *AcceptanceTest 컨벤션(@SpringBootTest + @AutoConfigureMockMvc + MockMvc)을 따른다.
 * Cucumber 인프라는 본 프로젝트에 도입되지 않았으므로(SoT 의 Cucumber 절은 미적용 청사진),
 * 동일 도메인의 실제 인수 테스트 패턴을 그대로 재사용한다.
 *
 * 이 테스트는 RED 단계 산출물이다.
 * /loadtest/token, /loadtest/seed, LoadTestSeed* DTO 가 아직 없으므로 컴파일/실행이 실패해야 정상이다.
 */
@SpringBootTest
@AutoConfigureMockMvc
@ActiveProfiles("loadtest")
class LoadTestHarnessAcceptanceTest : LoadTestPostgresSupport() {

    @Autowired
    private lateinit var mockMvc: MockMvc

    @Autowired
    private lateinit var jwtTokenProvider: JwtTokenProvider

    // DI 컨테이너의 ObjectMapper 빈은 Jackson 3(tools.jackson) 타입이라 com.fasterxml 타입으로는
    // autowire 되지 않는다. 응답 JSON 파싱용이므로 기존 테스트 컨벤션대로 직접 생성한다.
    private val objectMapper = ObjectMapper()

    @Test
    fun `loadtest 토큰으로 보호 엔드포인트를 호출한다`() {
        // given: 시드된 사용자 1명 — seed 로 user 를 만들고 그 범위의 첫 id 를 사용
        val seedResponse = mockMvc.post(SEED_PATH) {
            contentType = MediaType.APPLICATION_JSON
            content = """{"userCount":1,"matchesPerUser":1}"""
        }.andExpect {
            status { isOk() }
        }.andReturn().response.contentAsString

        val seededUserId = objectMapper.readTree(seedResponse).get("seededUserIdFrom").asLong()

        // when: GET /loadtest/token?userId={id}
        val tokenResponse = mockMvc.get(TOKEN_PATH) {
            param("userId", seededUserId.toString())
        }.andExpect {
            status { isOk() }
            jsonPath("$.accessToken") { exists() }
        }.andReturn().response.contentAsString

        val accessToken = objectMapper.readTree(tokenResponse).get("accessToken").asText()

        // then: 그 accessToken 으로 보호 엔드포인트(GET /users/me) 호출 시 200
        mockMvc.get("/users/me") {
            header("Authorization", "Bearer $accessToken")
        }.andExpect {
            status { isOk() }
            jsonPath("$.id") { value(seededUserId) }
        }
    }

    @Test
    fun `대량 시드 요청은 사용자 매치 쿼터 행 수를 응답한다`() {
        mockMvc.post(SEED_PATH) {
            contentType = MediaType.APPLICATION_JSON
            content = """{"userCount":5,"matchesPerUser":10,"quartersPerMatch":4}"""
        }.andExpect {
            status { isOk() }
            jsonPath("$.usersCreated") { value(5) }
            jsonPath("$.matchesCreated") { value(50) }
            jsonPath("$.quartersCreated") { value(200) }
            jsonPath("$.seededUserIdFrom") { exists() }
            jsonPath("$.seededUserIdTo") { exists() }
        }
    }

    @Test
    fun `quartersPerMatch 미지정이면 매치당 4쿼터를 생성한다`() {
        // edge-case: quartersPerMatch 기본값(미지정) → matchesPerUser * 4
        mockMvc.post(SEED_PATH) {
            contentType = MediaType.APPLICATION_JSON
            content = """{"userCount":2,"matchesPerUser":3}"""
        }.andExpect {
            status { isOk() }
            jsonPath("$.usersCreated") { value(2) }
            jsonPath("$.matchesCreated") { value(6) }
            jsonPath("$.quartersCreated") { value(24) }
        }
    }

    @Test
    fun `userCount 가 0 이면 400 으로 거부한다`() {
        // unhappy: Bean Validation (@field:Positive / @field:Min)
        mockMvc.post(SEED_PATH) {
            contentType = MediaType.APPLICATION_JSON
            content = """{"userCount":0,"matchesPerUser":10}"""
        }.andExpect {
            status { isBadRequest() }
        }
    }

    @Test
    fun `matchesPerUser 가 음수이면 400 으로 거부한다`() {
        mockMvc.post(SEED_PATH) {
            contentType = MediaType.APPLICATION_JSON
            content = """{"userCount":5,"matchesPerUser":-1}"""
        }.andExpect {
            status { isBadRequest() }
        }
    }

    companion object {
        private const val SEED_PATH = "/loadtest/seed"
        private const val TOKEN_PATH = "/loadtest/token"
    }
}
