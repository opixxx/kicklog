package com.opixxx.kicklog.loadtest

import com.opixxx.kicklog.common.security.JwtTokenProvider
import org.assertj.core.api.Assertions.assertThat
import org.junit.jupiter.api.DisplayName
import org.junit.jupiter.api.Test
import org.springframework.beans.factory.annotation.Autowired
import org.springframework.boot.test.context.SpringBootTest
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc
import org.springframework.context.ApplicationContext
import org.springframework.http.HttpHeaders
import org.springframework.test.context.ActiveProfiles
import org.springframework.test.web.servlet.MockMvc
import org.springframework.test.web.servlet.get

/**
 * Edge 1 (보안 격리) — prod 에서 `GET /loadtest/ext` 는 **존재하지 않아야 한다**.
 *
 * 이 엔드포인트는 인증 없이 외부 지연을 주입할 수 있는 장치다. 운영에 노출되면 그대로
 * 증폭 공격 도구가 된다. 방어는 `@Profile("loadtest & !prod")` 단일 기준이므로
 * (EXEC_PLAN 위험도 항목) 회귀가 생기면 즉시 깨지게 고정한다.
 *
 * DB 는 테스트 프로파일의 H2 를 쓴다(이 경로는 DB 를 타지 않으므로 Testcontainers 불필요).
 * 프로파일 겹침은 `@Profile` 빈 필터링과 무관하다 — 격리 검증 대상은 빈 등록 여부다.
 */
@SpringBootTest
@AutoConfigureMockMvc
@ActiveProfiles("prod", "test")
class LoadTestExternalProdIsolationTest {

    @Autowired
    private lateinit var mockMvc: MockMvc

    @Autowired
    private lateinit var jwtTokenProvider: JwtTokenProvider

    @Autowired
    private lateinit var context: ApplicationContext

    @Test
    @DisplayName("prod 에서는 W-EXT 관련 빈이 아예 등록되지 않는다")
    fun `prod 에서 loadtest 하네스 빈은 존재하지 않는다`() {
        assertThat(context.getBeanNamesForType(LoadTestController::class.java)).isEmpty()
        assertThat(context.getBeanNamesForType(LoadTestUpstreamClient::class.java)).isEmpty()
        assertThat(context.getBeanNamesForType(LoadTestHttpClientConfig::class.java)).isEmpty()
    }

    @Test
    @DisplayName("prod 에서 미인증 요청은 운영 보안 체인이 401 로 막는다")
    fun `prod 에서 ext 라우트는 인증 없이 접근할 수 없다`() {
        mockMvc.get("/loadtest/ext") {
            param("delayMs", "50")
        }.andExpect {
            status { isUnauthorized() }
        }
    }

    @Test
    @DisplayName("prod 에서 인증된 요청이어도 404 — 라우트 매핑 자체가 없다")
    fun `prod 에서 ext 라우트는 인증되어도 존재하지 않는다`() {
        val accessToken = jwtTokenProvider.createAccessToken(1L)

        mockMvc.get("/loadtest/ext") {
            header(HttpHeaders.AUTHORIZATION, "Bearer $accessToken")
            param("delayMs", "50")
        }.andExpect {
            status { isNotFound() }
        }
    }
}

/**
 * Edge 1 (심화) — `prod` 와 `loadtest` 가 **동시에** 활성인 사고 상황에서도 라우트는 없어야 한다.
 *
 * `& !prod` 조건이 존재하는 이유가 정확히 이 경우다. 이때 전용 SecurityFilterChain
 * ([LoadTestSecurityConfig], `@Profile("loadtest")`)은 등록되어 loadtest 하위 경로가 permitAll 이
 * 되므로, 핸들러가 남아 있다면 **인증 없이 200** 이 떨어진다. 즉 이 테스트가 깨지는 순간이
 * 바로 운영 노출이다.
 */
@SpringBootTest
@AutoConfigureMockMvc
@ActiveProfiles("prod", "loadtest", "test")
class LoadTestExternalProdAndLoadtestIsolationTest {

    @Autowired
    private lateinit var mockMvc: MockMvc

    @Autowired
    private lateinit var context: ApplicationContext

    @Test
    @DisplayName("prod + loadtest 동시 활성에서도 ext 라우트는 404")
    fun `prod 가 함께 활성이면 ext 라우트는 등록되지 않는다`() {
        assertThat(context.getBeanNamesForType(LoadTestController::class.java)).isEmpty()

        mockMvc.get("/loadtest/ext") {
            param("delayMs", "50")
        }.andExpect {
            status { isNotFound() }
        }
    }
}
