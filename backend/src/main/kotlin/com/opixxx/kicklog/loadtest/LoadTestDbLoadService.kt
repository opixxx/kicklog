package com.opixxx.kicklog.loadtest

import org.springframework.context.annotation.Profile
import org.springframework.jdbc.core.JdbcTemplate
import org.springframework.stereotype.Service

/**
 * W-DB-POOL 워크로드 — **DB 커넥션을 정해진 시간만큼 붙잡는다**.
 *
 * **왜 인위적인 지연을 주입하는가**
 *
 * 가설 H2 는 "가상 스레드는 스레드가 천장일 때만 유효하고, 커넥션 풀이 천장이면 무효"다.
 * 이를 검증하려면 **풀이 실제로 구속 자원인 구간**이 필요하다. 그런데 현실 쿼리로는 그 구간을
 * 이 측정 환경에서 만들 수 없다 — 시즌 집계가 p50 3.3ms 라(ADR-0014 의 DB 집계 전환 효과)
 * 풀 10 의 천장이 `10 ÷ 0.0033 ≈ 3,000 rps` 인데, Postgres·k6·백엔드가 8 vCPU 를 나눠 쓰는
 * 호스트는 거기에 한참 못 미친다. 풀을 2 로 낮춰도 천장이 ~2,000 rps 라 여전히 구속되지 않는다.
 *
 * 그래서 W-EXT 에서 외부 의존에 500ms 를 주입한 것과 **대칭으로** DB 에도 지연을 주입한다.
 * 풀 10 · 지연 50ms 면 천장이 `10 ÷ 0.05` = 200 rps 로 내려와, 호스트가 한참 여유인 상태에서
 * 풀 구속 구간을 관측할 수 있다. 측정하려는 것은 쿼리의 내용이 아니라 **커넥션 점유 시간**이므로
 * 점유 시간을 직접 통제하는 쪽이 오히려 정확하다.
 *
 * **트랜잭션을 걸지 않는 이유**: `JdbcTemplate` 은 쿼리 한 건 동안만 커넥션을 빌렸다 돌려준다.
 * 즉 점유 시간 = 주입 지연이 되어 천장 계산(`풀 크기 ÷ 점유 시간`)이 정확히 성립한다.
 * `@Transactional` 을 걸면 메서드 전체가 점유 구간이 되어 다른 작업까지 점유 시간에 섞인다.
 * 실제 운영 코드는 트랜잭션을 쓰므로 점유 시간이 이보다 길다 — 즉 **이 측정은 낙관적인 쪽**이다.
 */
@Service
@Profile("loadtest & !prod")
class LoadTestDbLoadService(
    private val jdbcTemplate: JdbcTemplate,
) {

    /**
     * HikariCP 커넥션을 [delayMs] 만큼 점유한다.
     *
     * `pg_sleep` 은 **DB 서버 쪽에서** 잠든다 — 애플리케이션 스레드는 응답을 기다리며 블로킹되고
     * 커넥션은 그동안 점유 상태다. 애플리케이션에서 `Thread.sleep` 을 하면 커넥션을 쥐지 않으므로
     * 풀 구속을 재현하지 못한다. 재현하려는 상황이 "느린 쿼리"라서 DB 쪽 지연이어야 한다.
     *
     * @return 실제 블로킹된 시간(ms). 주입값보다 크게 벌어지면 풀 대기가 섞인 것이다.
     */
    fun holdConnection(delayMs: Int): Long {
        val startedAt = System.nanoTime()
        jdbcTemplate.queryForObject(SLEEP_QUERY, Int::class.java, delayMs / MILLIS_PER_SECOND)
        return (System.nanoTime() - startedAt) / NANOS_PER_MILLI
    }

    companion object {
        // pg_sleep 은 void 를 반환하므로 FROM 절에 두고 상수를 투영한다.
        private const val SLEEP_QUERY = "SELECT 1 FROM pg_sleep(?)"
        private const val MILLIS_PER_SECOND = 1_000.0
        private const val NANOS_PER_MILLI = 1_000_000
    }
}
