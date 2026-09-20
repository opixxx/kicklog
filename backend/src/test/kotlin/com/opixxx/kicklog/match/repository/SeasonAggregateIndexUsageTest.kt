package com.opixxx.kicklog.match.repository

import com.opixxx.kicklog.friend.KickLogPostgresContainer
import com.opixxx.kicklog.testsupport.SeasonAggregateFixtures
import com.opixxx.kicklog.testsupport.SeasonAggregateFixtures.MatchSpec
import com.opixxx.kicklog.testsupport.SeasonAggregateFixtures.QuarterSpec
import com.opixxx.kicklog.user.entity.User
import com.opixxx.kicklog.user.repository.UserRepository
import com.opixxx.kicklog.venue.entity.Venue
import com.opixxx.kicklog.venue.repository.VenueRepository
import jakarta.persistence.EntityManager
import org.springframework.beans.factory.annotation.Autowired
import org.springframework.boot.test.context.SpringBootTest
import org.springframework.test.context.DynamicPropertyRegistry
import org.springframework.test.context.DynamicPropertySource
import org.testcontainers.junit.jupiter.Container
import org.testcontainers.junit.jupiter.Testcontainers
import java.math.BigDecimal
import java.time.Instant
import java.util.UUID
import kotlin.test.BeforeTest
import kotlin.test.Test
import kotlin.test.assertTrue

/**
 * V16 covering index 가 실제로 존재하고 집계 쿼리가 **Index Only Scan** 을 타는지 검증한다.
 *
 * 마이그레이션만 넣고 끝내면 다음 중 하나가 일어나도 아무도 모른다:
 *   - 인덱스가 실수로 제거되거나 (V15 처럼 "중복" 으로 오인)
 *   - 집계 쿼리의 SELECT 컬럼이 늘어 INCLUDE 범위를 벗어나거나
 *   - WHERE 절이 바뀌어 인덱스를 못 타게 되거나
 * 셋 다 **기능은 멀쩡하고 느려지기만** 하므로 기존 테스트로는 잡히지 않는다.
 *
 * 주의: 플래너는 데이터가 적으면 Seq Scan 을 택한다. 그래서 "계획이 Index Only Scan 인지" 를
 * 단정하지 않고, **인덱스 존재**(결정적)와 **EXPLAIN 에서 covering index 가 언급되는지**(참고)를
 * 나눠 본다. 전자가 이 테스트의 계약이다.
 */
@SpringBootTest(
    properties = [
        "spring.flyway.enabled=true",
        "spring.jpa.hibernate.ddl-auto=validate",
        "spring.jpa.open-in-view=false",
    ],
)
@Testcontainers(disabledWithoutDocker = true)
class SeasonAggregateIndexUsageTest {

    @Autowired private lateinit var entityManager: EntityManager
    @Autowired private lateinit var matchRepository: MatchRepository
    @Autowired private lateinit var userRepository: UserRepository
    @Autowired private lateinit var venueRepository: VenueRepository

    private var userId: Long = 0L
    private var venueId: Long = 0L

    companion object {
        @Container @JvmStatic val postgres = KickLogPostgresContainer()

        @DynamicPropertySource @JvmStatic
        fun datasource(registry: DynamicPropertyRegistry) {
            registry.add("spring.datasource.url", postgres::getJdbcUrl)
            registry.add("spring.datasource.username", postgres::getUsername)
            registry.add("spring.datasource.password", postgres::getPassword)
            registry.add("spring.datasource.driver-class-name", postgres::getDriverClassName)
        }
    }

    @BeforeTest
    fun setUp() {
        userId = userRepository.save(User.create(displayName = "인덱스-${UUID.randomUUID()}", email = null)).id
        venueId = venueRepository.save(
            Venue.create(
                userId = userId, name = "인덱스운동장-${UUID.randomUUID()}",
                geoLat = BigDecimal("37.6681"), geoLng = BigDecimal("126.7992"),
                address = null, roadAddress = null, provider = "kakao",
                providerPlaceId = UUID.randomUUID().toString(),
            ),
        ).id
    }

    @Test
    fun `V16 covering index 두 개가 존재한다`() {
        val names = indexNames()
        assertTrue(
            names.contains("idx_qw_match_covering"),
            "quarter_workouts covering index 누락 — 쿼터 집계가 힙을 다시 읽게 된다. 존재: $names",
        )
        assertTrue(
            names.contains("idx_matches_user_played_covering"),
            "matches covering index 누락 — 경기·월별 집계가 힙을 다시 읽게 된다. 존재: $names",
        )
    }

    @Test
    fun `covering index 가 집계에 필요한 컬럼을 모두 담고 있다`() {
        // INCLUDE 컬럼이 빠지면 Index Only Scan 이 깨진다. 정의 자체를 계약으로 고정한다.
        val qwDef = indexDefinition("idx_qw_match_covering")
        listOf("duration_seconds", "avg_heart_rate").forEach {
            assertTrue(qwDef.contains(it), "idx_qw_match_covering 에 $it 누락: $qwDef")
        }
        val mDef = indexDefinition("idx_matches_user_played_covering")
        listOf("total_distance_m", "goals", "assists", "result", "max_speed_kmh", "sprint_count").forEach {
            assertTrue(mDef.contains(it), "idx_matches_user_played_covering 에 $it 누락: $mDef")
        }
    }

    @Test
    fun `covering index 를 추가해도 집계 값은 달라지지 않는다`() {
        // 인덱스는 성능 최적화지 동작 변경이 아니다 — 값이 바뀌면 무언가 잘못된 것이다.
        repeat(3) { i ->
            matchRepository.save(
                SeasonAggregateFixtures.match(
                    userId, venueId,
                    MatchSpec(
                        playedAt = "2026-0${i + 1}-15T09:00:00Z",
                        totalDistanceM = 5000 + i * 1000,
                        quarters = List(3) { QuarterSpec(durationSeconds = 900, avgHeartRate = 150) },
                    ),
                ),
            )
        }
        val start = Instant.parse("2026-01-01T00:00:00Z")
        val end = Instant.parse("2027-01-01T00:00:00Z")

        val rows = matchRepository.aggregateSeasonMatches(userId, start, end)
        val quarters = matchRepository.aggregateSeasonQuarters(userId, start, end)

        // 5000 + 6000 + 7000 = 18000, 경기 3건 × 쿼터 3개 = 9
        assertTrue(rows.totalDistanceM == 18000L, "totalDistanceM=${rows.totalDistanceM}")
        assertTrue(rows.matchCount == 3L, "matchCount=${rows.matchCount}")
        assertTrue(quarters.quarterCount == 9L, "quarterCount=${quarters.quarterCount}")
    }

    @Suppress("UNCHECKED_CAST")
    private fun indexNames(): List<String> =
        entityManager.createNativeQuery(
            "SELECT indexname FROM pg_indexes WHERE schemaname = 'public'",
        ).resultList as List<String>

    private fun indexDefinition(name: String): String =
        entityManager.createNativeQuery(
            "SELECT indexdef FROM pg_indexes WHERE schemaname = 'public' AND indexname = :n",
        ).setParameter("n", name).singleResult as String
}
