package com.opixxx.kicklog.match.repository

import com.opixxx.kicklog.friend.KickLogPostgresContainer
import com.opixxx.kicklog.match.service.MatchResultType
import com.opixxx.kicklog.testsupport.SeasonAggregateFixtures
import com.opixxx.kicklog.testsupport.SeasonAggregateFixtures.MatchSpec
import com.opixxx.kicklog.testsupport.SeasonAggregateFixtures.QuarterSpec
import com.opixxx.kicklog.user.entity.User
import com.opixxx.kicklog.user.repository.UserRepository
import com.opixxx.kicklog.venue.entity.Venue
import com.opixxx.kicklog.venue.repository.VenueRepository
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
import kotlin.test.assertEquals

/**
 * EXEC_PLAN 2026-09-16 season-stat-sql-aggregation (3-B / B-3) — 집계 SQL 통합 테스트 ★ 본 작업의 핵심.
 *
 * `SeasonStatServiceTest` 는 완전 인메모리라 SQL 을 한 줄도 검증하지 못하고,
 * 기본 테스트 프로파일의 H2 는 `AT TIME ZONE` · `FILTER` · `::bigint` 같은 PostgreSQL 방언 차이를
 * 가려버린다. 따라서 **Testcontainers 실 PostgreSQL 16 + Flyway 스키마**로만 검증한다.
 *
 * 특히 다음 세 가지는 컴파일도 기존 테스트도 통과하면서 값만 조용히 틀리는 종류의 버그다.
 * 1. **fan-out** — matches ⨝ quarter_workouts 를 한 번에 집계하면 경기 1행이 쿼터 수만큼 복제되어
 *    `SUM(m.total_distance_m)` 이 쿼터 개수배가 된다. → 경기당 쿼터 3개로 잡는다.
 * 2. **UTC 월 경계** — `AT TIME ZONE 'UTC'` 를 빠뜨리면 서버 TZ 에 따라 경기가 다른 달로 간다.
 *    api-spec §8.1 이 "UTC playedAt.month 기준" 으로 못 박았다. → `2026-12-31T15:00:00Z` 로 잡는다.
 * 3. **COALESCE** — 0건이면 `SUM` 이 NULL 이라 Kotlin `Int` 매핑에서 터지거나 0 이 아닌 값이 된다.
 */
@SpringBootTest(
    properties = [
        "spring.flyway.enabled=true",
        "spring.jpa.hibernate.ddl-auto=validate",
        "spring.jpa.open-in-view=false",
    ],
)
@Testcontainers(disabledWithoutDocker = true)
class JpaMatchStoreSeasonAggregateIntegrationTest {

    @Autowired
    private lateinit var matchStore: JpaMatchStore

    @Autowired
    private lateinit var matchRepository: MatchRepository

    @Autowired
    private lateinit var venueRepository: VenueRepository

    @Autowired
    private lateinit var userRepository: UserRepository

    private val seasonStart: Instant = Instant.parse("2026-01-01T00:00:00Z")
    private val seasonEnd: Instant = Instant.parse("2027-01-01T00:00:00Z")

    // 테스트 간 격리는 사용자 단위로 한다 (매 테스트 새 user — 집계가 user_id 로 필터되므로 충분).
    private var userId: Long = 0L
    private var venueId: Long = 0L

    @BeforeTest
    fun setUp() {
        userId = saveUser()
        venueId = saveVenue()
    }

    @Test
    fun `aggregateSeasonMatches 는 쿼터 수와 무관하게 경기 지표를 1회만 합산한다`() {
        // 경기 2건 × 쿼터 3개. 조인 집계라면 totalDistanceM 이 12000 이 아니라 36000 이 된다.
        save(
            MatchSpec(
                playedAt = "2026-03-01T09:00:00Z", totalDistanceM = 5000, goals = 2, assists = 1,
                maxSpeedKmh = 29.4, sprintCount = 11, result = MatchResultType.WIN,
                quarters = List(3) { QuarterSpec(durationSeconds = 900, avgHeartRate = 150) },
            ),
        )
        save(
            MatchSpec(
                playedAt = "2026-05-01T09:00:00Z", totalDistanceM = 7000, goals = 1, assists = 2,
                maxSpeedKmh = 31.2, sprintCount = 19, result = MatchResultType.LOSS,
                quarters = List(3) { QuarterSpec(durationSeconds = 900, avgHeartRate = 120) },
            ),
        )

        val aggregate: SeasonMatchAggregate = matchStore.aggregateSeasonMatches(userId, seasonStart, seasonEnd)

        assertEquals(12000, aggregate.totalDistanceM)
        assertEquals(3, aggregate.totalGoals)
        assertEquals(3, aggregate.totalAssists)
        assertEquals(2, aggregate.matchCount)
        assertEquals(1, aggregate.winCount)
        assertEquals(0, aggregate.drawCount)
        assertEquals(1, aggregate.lossCount)
        assertEquals(31.2, aggregate.maxSpeedKmh)
        assertEquals(7000, aggregate.longestMatchDistanceM)
        assertEquals(19, aggregate.mostSprintCount)
    }

    @Test
    fun `aggregateSeasonMatches 는 result 가 NULL 인 경기를 승무패 어디에도 넣지 않는다`() {
        // 점수 미입력 경기 (result NULL) — COUNT(*) FILTER 가 NULL 을 삼키는지 확인.
        save(MatchSpec(playedAt = "2026-03-01T09:00:00Z", totalDistanceM = 1000, result = null))
        save(MatchSpec(playedAt = "2026-03-08T09:00:00Z", totalDistanceM = 2000, result = MatchResultType.WIN))

        val aggregate = matchStore.aggregateSeasonMatches(userId, seasonStart, seasonEnd)

        assertEquals(2, aggregate.matchCount)
        assertEquals(3000, aggregate.totalDistanceM)
        assertEquals(1, aggregate.winCount)
        assertEquals(0, aggregate.drawCount)
        assertEquals(0, aggregate.lossCount)
    }

    @Test
    fun `aggregateSeasonQuarters 는 기간 내 쿼터만 센다`() {
        save(
            MatchSpec(
                playedAt = "2026-03-01T09:00:00Z", totalDistanceM = 5000,
                quarters = List(3) { QuarterSpec(durationSeconds = 900, avgHeartRate = 150) },
            ),
        )
        save(
            MatchSpec(
                playedAt = "2026-05-01T09:00:00Z", totalDistanceM = 7000,
                quarters = listOf(QuarterSpec(durationSeconds = 600, avgHeartRate = 120)),
            ),
        )
        // 시즌 밖 경기의 쿼터는 세면 안 된다 (조인이 기간 필터 역할을 제대로 하는지).
        save(
            MatchSpec(
                playedAt = "2025-06-01T09:00:00Z", totalDistanceM = 9999,
                quarters = List(4) { QuarterSpec(durationSeconds = 900, avgHeartRate = 199) },
            ),
        )

        val aggregate: SeasonQuarterAggregate = matchStore.aggregateSeasonQuarters(userId, seasonStart, seasonEnd)

        assertEquals(4, aggregate.quarterCount)
        // 3*900*150 + 600*120 = 405000 + 72000 = 477000
        assertEquals(477_000L, aggregate.weightedHeartRateSum)
        assertEquals(3_300L, aggregate.totalDurationSeconds)
    }

    @Test
    fun `aggregateSeasonQuarters 는 쿼터 없는 경기가 섞여도 경기 수만큼 부풀지 않는다`() {
        save(MatchSpec(playedAt = "2026-03-01T09:00:00Z", totalDistanceM = 5000, quarters = emptyList()))
        save(
            MatchSpec(
                playedAt = "2026-04-01T09:00:00Z", totalDistanceM = 6000,
                quarters = List(2) { QuarterSpec(durationSeconds = 450, avgHeartRate = 160) },
            ),
        )

        val aggregate = matchStore.aggregateSeasonQuarters(userId, seasonStart, seasonEnd)

        assertEquals(2, aggregate.quarterCount)
        assertEquals(144_000L, aggregate.weightedHeartRateSum)   // 2*450*160
        assertEquals(900L, aggregate.totalDurationSeconds)
    }

    @Test
    fun `aggregateMonthlyDistance 는 UTC 월 기준으로 그룹핑한다`() {
        // KST(UTC+9) 로는 2027-01-01 06:00 — 서버 TZ 를 타면 12월이 아니라 1월(또는 다음 시즌)로 샌다.
        save(MatchSpec(playedAt = "2026-12-31T15:00:00Z", totalDistanceM = 4000))
        save(MatchSpec(playedAt = "2026-12-05T09:00:00Z", totalDistanceM = 2500))
        save(MatchSpec(playedAt = "2026-01-01T00:00:00Z", totalDistanceM = 1234))

        val monthly: List<MonthlyDistance> = matchStore.aggregateMonthlyDistance(userId, seasonStart, seasonEnd)

        // 데이터 있는 달만 월 오름차순으로 반환한다 (12칸 채우기는 Service 책임).
        assertEquals(listOf(1 to 1234, 12 to 6500), monthly.map { it.month to it.distanceM })
    }

    @Test
    fun `경기 0건이면 모든 집계가 0 을 반환한다`() {
        val matchAggregate = matchStore.aggregateSeasonMatches(userId, seasonStart, seasonEnd)
        val quarterAggregate = matchStore.aggregateSeasonQuarters(userId, seasonStart, seasonEnd)
        val monthly = matchStore.aggregateMonthlyDistance(userId, seasonStart, seasonEnd)

        // COALESCE 누락 시 NULL → Kotlin Int 매핑에서 터지거나 잘못된 값이 된다.
        assertEquals(0, matchAggregate.totalDistanceM)
        assertEquals(0, matchAggregate.totalGoals)
        assertEquals(0, matchAggregate.totalAssists)
        assertEquals(0, matchAggregate.matchCount)
        assertEquals(0, matchAggregate.winCount)
        assertEquals(0, matchAggregate.drawCount)
        assertEquals(0, matchAggregate.lossCount)
        assertEquals(0.0, matchAggregate.maxSpeedKmh)
        assertEquals(0, matchAggregate.longestMatchDistanceM)
        assertEquals(0, matchAggregate.mostSprintCount)

        assertEquals(0, quarterAggregate.quarterCount)
        assertEquals(0L, quarterAggregate.weightedHeartRateSum)
        assertEquals(0L, quarterAggregate.totalDurationSeconds)

        assertEquals(emptyList(), monthly)
    }

    @Test
    fun `다른 사용자의 경기는 집계에 포함되지 않는다`() {
        val otherUserId = saveUser()
        save(
            MatchSpec(
                playedAt = "2026-04-01T09:00:00Z", totalDistanceM = 99999, goals = 9, assists = 9,
                maxSpeedKmh = 34.9, sprintCount = 99, result = MatchResultType.WIN,
                quarters = List(4) { QuarterSpec(durationSeconds = 900, avgHeartRate = 200) },
            ),
            ownerId = otherUserId,
        )
        save(
            MatchSpec(
                playedAt = "2026-04-02T09:00:00Z", totalDistanceM = 5000, goals = 1, assists = 0,
                maxSpeedKmh = 20.0, sprintCount = 3, result = MatchResultType.WIN,
                quarters = listOf(QuarterSpec(durationSeconds = 900, avgHeartRate = 140)),
            ),
        )

        val matchAggregate = matchStore.aggregateSeasonMatches(userId, seasonStart, seasonEnd)
        val quarterAggregate = matchStore.aggregateSeasonQuarters(userId, seasonStart, seasonEnd)
        val monthly = matchStore.aggregateMonthlyDistance(userId, seasonStart, seasonEnd)

        assertEquals(1, matchAggregate.matchCount)
        assertEquals(5000, matchAggregate.totalDistanceM)
        assertEquals(20.0, matchAggregate.maxSpeedKmh)
        assertEquals(1, quarterAggregate.quarterCount)
        assertEquals(listOf(4 to 5000), monthly.map { it.month to it.distanceM })
    }

    @Test
    fun `기간 경계는 start 포함 end 미포함이다`() {
        save(MatchSpec(playedAt = "2025-12-31T23:59:59Z", totalDistanceM = 1))        // 시즌 직전 — 제외
        save(MatchSpec(playedAt = "2026-01-01T00:00:00Z", totalDistanceM = 1000))     // start 정각 — 포함
        save(MatchSpec(playedAt = "2026-12-31T23:59:59Z", totalDistanceM = 2000))     // 시즌 마지막 순간 — 포함
        save(MatchSpec(playedAt = "2027-01-01T00:00:00Z", totalDistanceM = 4))        // end 정각 — 제외

        val aggregate = matchStore.aggregateSeasonMatches(userId, seasonStart, seasonEnd)

        assertEquals(2, aggregate.matchCount)
        assertEquals(3000, aggregate.totalDistanceM)
    }

    // MARK: - 헬퍼

    private fun save(spec: MatchSpec, ownerId: Long = userId) {
        matchRepository.save(SeasonAggregateFixtures.match(ownerId, venueId, spec))
    }

    private fun saveUser(): Long {
        return userRepository.save(
            User.create(displayName = "집계사용자-${UUID.randomUUID()}", email = null),
        ).id
    }

    private fun saveVenue(): Long {
        return venueRepository.save(
            Venue.create(
                userId = userId,
                name = "집계운동장-${UUID.randomUUID()}",
                geoLat = BigDecimal("37.6681"),
                geoLng = BigDecimal("126.7992"),
                address = null,
                roadAddress = null,
                provider = "kakao",
                providerPlaceId = UUID.randomUUID().toString(),
            ),
        ).id
    }

    /**
     * 불변식: 월별 이동거리의 총합은 시즌 총거리와 같아야 한다.
     *
     * 두 값은 서로 다른 쿼리(①경기 집계 / ③월별 GROUP BY)에서 나오므로, 어긋난다면
     * WHERE 조건 불일치·월 계산 오류·fan-out 중 하나가 일어났다는 신호다.
     * 개별 값을 고정하는 것과 별개로 **두 쿼리 사이의 정합성**을 직접 못 박는다.
     */
    @Test
    fun `월별 이동거리의 합은 시즌 총거리와 일치한다`() {
        // 여러 달 + 쿼터 수 제각각 — fan-out 이 있으면 ①과 ③이 다르게 부풀어 깨진다.
        save(
            MatchSpec(
                playedAt = "2026-01-10T09:00:00Z", totalDistanceM = 5000,
                quarters = List(1) { QuarterSpec(durationSeconds = 900, avgHeartRate = 150) },
            ),
        )
        save(
            MatchSpec(
                playedAt = "2026-03-05T09:00:00Z", totalDistanceM = 7000,
                quarters = List(3) { QuarterSpec(durationSeconds = 900, avgHeartRate = 150) },
            ),
        )
        save(
            MatchSpec(
                playedAt = "2026-03-20T09:00:00Z", totalDistanceM = 6000,
                quarters = List(2) { QuarterSpec(durationSeconds = 900, avgHeartRate = 150) },
            ),
        )
        // UTC 로는 12월 (KST 로는 2027-01-01)
        save(
            MatchSpec(
                playedAt = "2026-12-31T15:00:00Z", totalDistanceM = 4000,
                quarters = List(4) { QuarterSpec(durationSeconds = 900, avgHeartRate = 150) },
            ),
        )

        val matchAggregate = matchStore.aggregateSeasonMatches(userId, seasonStart, seasonEnd)
        val monthly = matchStore.aggregateMonthlyDistance(userId, seasonStart, seasonEnd)

        assertEquals(22000, matchAggregate.totalDistanceM)
        assertEquals(matchAggregate.totalDistanceM, monthly.sumOf { it.distanceM })
    }

    companion object {
        @Container
        @JvmStatic
        val postgres = KickLogPostgresContainer()

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
