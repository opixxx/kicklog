package com.opixxx.kicklog.loadtest

import org.assertj.core.api.Assertions.assertThat
import org.junit.jupiter.api.Test
import org.springframework.beans.factory.annotation.Autowired
import org.springframework.boot.test.context.SpringBootTest
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc
import org.springframework.test.context.ActiveProfiles
import org.springframework.test.web.servlet.MockMvc
import org.springframework.test.web.servlet.get
import javax.sql.DataSource

/**
 * `/loadtest/db` — DB 커넥션 점유 주입(W-DB-POOL)의 계약 검증.
 *
 * 이 엔드포인트의 존재 이유는 "커넥션을 **정확히 요청한 시간만큼** 붙잡는 것"이다.
 * 점유 시간이 요청값과 어긋나면 천장 계산(`풀 크기 ÷ 점유 시간`)이 성립하지 않아
 * 가설 H2 의 검증 장치로 쓸 수 없다. 그래서 지연의 **하한**을 테스트로 고정한다.
 *
 * H2 는 `pg_sleep` 이 없으므로 실제 PostgreSQL 이 필요하다 — [LoadTestPostgresSupport].
 */
@SpringBootTest
@AutoConfigureMockMvc
@ActiveProfiles("loadtest")
class LoadTestDbLoadEndpointTest : LoadTestPostgresSupport() {

    @Autowired
    private lateinit var mockMvc: MockMvc

    @Autowired
    private lateinit var dataSource: DataSource

    @Test
    fun `요청한 지연만큼 커넥션을 점유하고 실제 경과 시간을 돌려준다`() {
        val requested = 120

        mockMvc.get("/loadtest/db") {
            param("delayMs", requested.toString())
        }.andExpect {
            status { isOk() }
            jsonPath("$.requestedDelayMs") { value(requested) }
            // 지연은 DB 쪽에서 발생하므로 경과는 요청값 이상이어야 한다.
            // 상한을 걸지 않는 이유는 CI 부하에 따라 흔들리기 때문이다 — 하한만이 계약이다.
            jsonPath("$.elapsedMs") { value(org.hamcrest.Matchers.greaterThanOrEqualTo(requested)) }
        }
    }

    @Test
    fun `delayMs 를 생략하면 설정의 기본값이 적용된다`() {
        // 기본값 50ms 는 "풀 10 기준 천장 200 rps" 를 만들기 위해 고른 값이다.
        // 이 값이 조용히 바뀌면 예측 천장과 실측이 어긋나므로 테스트로 못 박는다.
        mockMvc.get("/loadtest/db").andExpect {
            status { isOk() }
            jsonPath("$.requestedDelayMs") { value(50) }
            jsonPath("$.elapsedMs") { value(org.hamcrest.Matchers.greaterThanOrEqualTo(50)) }
        }
    }

    @Test
    fun `음수 지연은 외부 호출 경로와 같은 검증 메시지로 거부된다`() {
        mockMvc.get("/loadtest/db") {
            param("delayMs", "-1")
        }.andExpect {
            status { isBadRequest() }
            jsonPath("$.code") { value("VALIDATION_FAILED") }
            jsonPath("$.message") { value(org.hamcrest.Matchers.containsString("범위여야 합니다")) }
        }
    }

    @Test
    fun `상한을 넘는 지연은 거부된다`() {
        // 상한이 없으면 실수로 큰 값을 넣었을 때 커넥션이 그만큼 묶여 측정 자체가 멈춘다.
        mockMvc.get("/loadtest/db") {
            param("delayMs", "10001")
        }.andExpect {
            status { isBadRequest() }
            jsonPath("$.code") { value("VALIDATION_FAILED") }
        }
    }

    @Test
    fun `점유가 끝나면 커넥션이 풀로 반납된다`() {
        // 반납되지 않으면 풀이 요청 몇 건 만에 고갈되어, 측정이 "풀 구속"이 아니라
        // "커넥션 누수"를 재게 된다. 풀 크기보다 많이 호출해 고갈되지 않음을 확인한다.
        val poolSize = dataSource.unwrap(com.zaxxer.hikari.HikariDataSource::class.java).maximumPoolSize

        repeat(poolSize + 3) {
            mockMvc.get("/loadtest/db") {
                param("delayMs", "1")
            }.andExpect {
                status { isOk() }
            }
        }

        assertThat(poolSize).isGreaterThan(0)
    }
}
