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
 * (보안 회귀) prod 프로파일에서 loadtest 라우트(token/seed/ping)는 인증 없이 접근할 수 없어야 한다(401).
 *
 * loadtest 빈은 모두 @Profile("loadtest"...) 이라 prod 에선 핸들러도, 전용 SecurityFilterChain
 * (LoadTestSecurityConfig)도 등록되지 않는다 → 메인 SecurityConfig 의 anyRequest().authenticated()
 * 가 미인증 요청을 401 로 차단한다.
 *
 * 이 테스트는 프로파일 격리 회귀를 막는 안전장치다 — loadtest 토큰 발급(인증 우회)·대량 시드가
 * 운영에서 인증 없이 노출되면 즉시 깨진다.
 */
@SpringBootTest
@AutoConfigureMockMvc
@ActiveProfiles("prod")
class LoadTestProfileIsolationTest : LoadTestPostgresSupport() {

    @Autowired
    private lateinit var mockMvc: MockMvc

    @Test
    fun `prod 에서 loadtest token 라우트는 인증 없이 접근할 수 없다`() {
        mockMvc.get("/loadtest/token") {
            param("userId", "1")
        }.andExpect {
            status { isUnauthorized() }
        }
    }

    @Test
    fun `prod 에서 loadtest seed 라우트는 인증 없이 접근할 수 없다`() {
        mockMvc.post("/loadtest/seed") {
            contentType = org.springframework.http.MediaType.APPLICATION_JSON
            content = """{"userCount":5,"matchesPerUser":10}"""
        }.andExpect {
            status { isUnauthorized() }
        }
    }

    @Test
    fun `prod 에서 loadtest ping 라우트는 인증 없이 접근할 수 없다`() {
        mockMvc.get("/loadtest/ping").andExpect {
            status { isUnauthorized() }
        }
    }
}
