package com.opixxx.kicklog.loadtest

import com.opixxx.kicklog.match.service.MatchResultType
import org.assertj.core.api.Assertions.assertThat
import org.junit.jupiter.api.Test
import org.springframework.beans.factory.annotation.Autowired
import org.springframework.boot.test.context.SpringBootTest
import org.springframework.jdbc.core.JdbcTemplate
import org.springframework.test.context.ActiveProfiles
import org.springframework.test.context.DynamicPropertyRegistry
import org.springframework.test.context.DynamicPropertySource
import org.testcontainers.containers.PostgreSQLContainer
import org.testcontainers.junit.jupiter.Container
import org.testcontainers.junit.jupiter.Testcontainers

/**
 * (3-B) LoadTestSeedService 통합 — 실제 PostgreSQL(Testcontainers) 에 대량 시드.
 *
 * - userCount=5 · matchesPerUser=10 · quartersPerMatch=4 → users 5 / matches 50 / quarter_workouts 200 행
 * - 시드된 각 matches.result == MatchResultType.derive(team_goals, opponent_goals) (Aggregate invariant 일관성)
 *
 * Flyway 실제 스키마 + JPA validate 로 운영 스키마와 동일 조건에서 검증한다.
 *
 * RED 단계: LoadTestSeedService / LoadTestSeedCommand 가 아직 없어 컴파일 실패해야 정상.
 */
@SpringBootTest(
    properties = [
        "spring.flyway.enabled=true",
        "spring.jpa.hibernate.ddl-auto=validate",
    ],
)
@ActiveProfiles("loadtest")
@Testcontainers(disabledWithoutDocker = true)
class LoadTestSeedServiceIntegrationTest {

    @Autowired
    private lateinit var loadTestSeedService: LoadTestSeedService

    @Autowired
    private lateinit var jdbcTemplate: JdbcTemplate

    @Test
    fun `시드는 요청한 사용자 매치 쿼터 수만큼 행을 생성한다`() {
        val result = loadTestSeedService.seed(
            LoadTestSeedCommand(
                userCount = 5,
                matchesPerUser = 10,
                quartersPerMatch = 4,
                friendshipsPerUser = 0,
            ),
        )

        assertThat(result.usersCreated).isEqualTo(5)
        assertThat(result.matchesCreated).isEqualTo(50)
        assertThat(result.quartersCreated).isEqualTo(200)
        assertThat(result.seededUserIdFrom).isLessThanOrEqualTo(result.seededUserIdTo)

        // 시드된 범위 안에서 실제 DB 행 수도 일치해야 한다.
        val usersInRange = jdbcTemplate.queryForObject(
            "select count(*) from users where id between ? and ?",
            Int::class.java,
            result.seededUserIdFrom,
            result.seededUserIdTo,
        )
        assertThat(usersInRange).isEqualTo(5)

        val matchesInRange = jdbcTemplate.queryForObject(
            "select count(*) from matches where user_id between ? and ?",
            Int::class.java,
            result.seededUserIdFrom,
            result.seededUserIdTo,
        )
        assertThat(matchesInRange).isEqualTo(50)

        val quartersInRange = jdbcTemplate.queryForObject(
            """
            select count(*) from quarter_workouts qw
            join matches m on m.id = qw.match_id
            where m.user_id between ? and ?
            """.trimIndent(),
            Int::class.java,
            result.seededUserIdFrom,
            result.seededUserIdTo,
        )
        assertThat(quartersInRange).isEqualTo(200)
    }

    @Test
    fun `시드된 모든 매치의 result 는 team_goals 와 opponent_goals 로 derive 한 값과 일치한다`() {
        val result = loadTestSeedService.seed(
            LoadTestSeedCommand(userCount = 3, matchesPerUser = 5),
        )

        val rows = jdbcTemplate.queryForList(
            "select team_goals, opponent_goals, result from matches where user_id between ? and ?",
            result.seededUserIdFrom,
            result.seededUserIdTo,
        )

        assertThat(rows).isNotEmpty()
        rows.forEach { row ->
            val teamGoals = (row["team_goals"] as Number?)?.toInt()
            val opponentGoals = (row["opponent_goals"] as Number?)?.toInt()
            val storedResult = row["result"] as String?
            val expected = MatchResultType.derive(teamGoals, opponentGoals)?.name
            assertThat(storedResult).isEqualTo(expected)
        }
    }

    companion object {
        @Container
        @JvmStatic
        val postgres = PostgreSQLContainer<Nothing>("postgres:16-alpine")

        @DynamicPropertySource
        @JvmStatic
        fun datasource(registry: DynamicPropertyRegistry) {
            registry.add("spring.datasource.url", postgres::getJdbcUrl)
            registry.add("spring.datasource.username", postgres::getUsername)
            registry.add("spring.datasource.password", postgres::getPassword)
            registry.add("spring.datasource.driver-class-name", postgres::getDriverClassName)
        }
    }
}
