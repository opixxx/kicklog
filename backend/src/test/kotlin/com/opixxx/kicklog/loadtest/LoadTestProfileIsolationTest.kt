package com.opixxx.kicklog.loadtest

import org.junit.jupiter.api.Test
import org.springframework.beans.factory.annotation.Autowired
import org.springframework.boot.test.context.SpringBootTest
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc
import org.springframework.test.context.ActiveProfiles
import org.springframework.test.web.servlet.MockMvc
import org.springframework.test.web.servlet.get
import org.springframework.test.web.servlet.post

/**
 * (3-B Edge / 보안 회귀) prod 프로파일에서는 loadtest 라우트(token/seed/ping)가 미존재(404)해야 한다.
 *
 * 모든 loadtest 빈은 @Profile("loadtest") 이므로 prod 부팅 시 빈이 등록되지 않아
 * 핸들러 매핑 자체가 없다 → Spring Security 의 인증 게이트보다 먼저 404 가 떨어진다.
 *
 * 이 테스트는 프로파일 격리 회귀를 막는 안전장치다.
 * loadtest 토큰 발급(인증 우회)·대량 시드 엔드포인트가 운영에 새어나가면 즉시 깨진다.
 *
 * RED 단계: 본 테스트는 신규 엔드포인트 추가 후에도 prod 에서 404 를 유지하는지 검증한다.
 * (현재는 ping 조차 loadtest 전용이므로 prod 에서 항상 404 — 신규 추가가 이 규칙을 깨면 RED)
 */
@SpringBootTest
@AutoConfigureMockMvc
@ActiveProfiles("prod")
class LoadTestProfileIsolationTest : LoadTestPostgresSupport() {

    @Autowired
    private lateinit var mockMvc: MockMvc

    @Test
    fun `prod 에서 loadtest token 라우트는 존재하지 않는다`() {
        mockMvc.get("/loadtest/token") {
            param("userId", "1")
        }.andExpect {
            status { isNotFound() }
        }
    }

    @Test
    fun `prod 에서 loadtest seed 라우트는 존재하지 않는다`() {
        mockMvc.post("/loadtest/seed") {
            contentType = org.springframework.http.MediaType.APPLICATION_JSON
            content = """{"userCount":5,"matchesPerUser":10}"""
        }.andExpect {
            status { isNotFound() }
        }
    }

    @Test
    fun `prod 에서 loadtest ping 라우트는 존재하지 않는다`() {
        mockMvc.get("/loadtest/ping").andExpect {
            status { isNotFound() }
        }
    }
}
