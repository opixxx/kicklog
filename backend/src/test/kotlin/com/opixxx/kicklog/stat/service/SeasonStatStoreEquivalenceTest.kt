package com.opixxx.kicklog.stat.service

import com.opixxx.kicklog.friend.KickLogPostgresContainer
import com.opixxx.kicklog.friend.service.FriendshipAuthorizer
import com.opixxx.kicklog.match.repository.InMemoryMatchRepository
import com.opixxx.kicklog.match.repository.JpaMatchStore
import com.opixxx.kicklog.match.repository.MatchRepository
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
import java.util.UUID
import kotlin.test.BeforeTest
import kotlin.test.Test
import kotlin.test.assertEquals

/**
 * EXEC_PLAN 2026-09-16 season-stat-sql-aggregation (3-B / B-4) — 두 구현 동등성 ★ 값 보존의 최종 관문.
 *
 * `SeasonStatService` 에 **같은 데이터를 담은 두 저장소**를 각각 주입해 돌린 뒤
 * 반환된 `SeasonStat` 이 필드 단위로 완전히 같은지 비교한다.
 *
 * - `InMemoryMatchRepository` = 참조 구현 (현재 Kotlin 집계 로직)
 * - `JpaMatchStore` = 집계 SQL (실 PostgreSQL)
 *
 * 한 fixture 에 **쿼터 복수 · 빈 쿼터 · UTC 월 경계 · durationSeconds 0 · 시즌 밖 경기 · 타 사용자 경기**
 * 를 전부 섞어 넣는다. 조용한 값 오류(fan-out 중복 합산, 월 경계 어긋남, NULL→0 누락)는
 * 컴파일도 기존 테스트도 통과하므로 이 비교가 마지막 방어선이다.
 *
 * H2 는 native 집계 SQL 의 방언 차이를 가려버리므로 **반드시 Testcontainers 실 PostgreSQL** 로 돌린다.
 */
@SpringBootTest(
    properties = [
        "spring.flyway.enabled=true",
        "spring.jpa.hibernate.ddl-auto=validate",
        "spring.jpa.open-in-view=false",
    ],
)
@Testcontainers(disabledWithoutDocker = true)
class SeasonStatStoreEquivalenceTest {

    @Autowired
    private lateinit var matchRepository: MatchRepository

    @Autowired
    private lateinit var jpaMatchStore: JpaMatchStore

    @Autowired
    private lateinit var venueRepository: VenueRepository

    @Autowired
    private lateinit var userRepository: UserRepository

    @Autowired
    private lateinit var friendshipAuthorizer: FriendshipAuthorizer

    private val inMemoryMatchRepository = InMemoryMatchRepository()

    private lateinit var inMemoryService: SeasonStatService
    private lateinit var jpaService: SeasonStatService

    private var userId: Long = 0L
    private var otherUserId: Long = 0L
    private var venueId: Long = 0L

    @BeforeTest
    fun setUp() {
        userId = saveUser()
        otherUserId = saveUser()
        venueId = saveVenue()
        inMemoryService = SeasonStatService(inMemoryMatchRepository, friendshipAuthorizer)
        jpaService = SeasonStatService(jpaMatchStore, friendshipAuthorizer)
    }

    @Test
    fun `쿼터 복수와 빈 쿼터와 월 경계와 0 duration 이 섞인 시즌에서 두 구현이 같은 결과를 낸다`() {
        val specs = listOf(
            // ① 쿼터 3개 — fan-out canary
            MatchSpec(
                playedAt = "2026-03-01T09:00:00Z", totalDistanceM = 5000, goals = 2, assists = 1,
                maxSpeedKmh = 29.4, sprintCount = 11, result = MatchResultType.WIN,
                quarters = List(3) { QuarterSpec(durationSeconds = 900, avgHeartRate = 150, distanceM = 1600) },
            ),
            // ② 쿼터 없음 — LEFT JOIN 누락 시 경기가 통째로 사라진다
            MatchSpec(
                playedAt = "2026-06-15T09:00:00Z", totalDistanceM = 7000, goals = 1, assists = 2,
                maxSpeedKmh = 31.2, sprintCount = 19, result = MatchResultType.DRAW,
                quarters = emptyList(),
            ),
            // ③ durationSeconds 0 — 가중평균 분모 기여 0
            MatchSpec(
                playedAt = "2026-08-01T09:00:00Z", totalDistanceM = 3000, goals = 0, assists = 0,
                maxSpeedKmh = 18.0, sprintCount = 2, result = MatchResultType.LOSS,
                quarters = listOf(
                    QuarterSpec(durationSeconds = 0, avgHeartRate = 199),
                    QuarterSpec(durationSeconds = 0, avgHeartRate = 88),
                ),
            ),
            // ④ UTC 월 경계 — KST 로는 2027-01-01 이지만 12월이어야 한다
            MatchSpec(
                playedAt = "2026-12-31T15:00:00Z", totalDistanceM = 4000, goals = 3, assists = 0,
                maxSpeedKmh = 25.0, sprintCount = 7, result = MatchResultType.WIN,
                quarters = listOf(QuarterSpec(durationSeconds = 601, avgHeartRate = 133)),
            ),
            // ⑤ 같은 달 두 번째 경기 — 월별 합산
            MatchSpec(
                playedAt = "2026-12-05T09:00:00Z", totalDistanceM = 2500, goals = 0, assists = 1,
                maxSpeedKmh = 22.0, sprintCount = 4, result = MatchResultType.LOSS,
                quarters = List(2) { QuarterSpec(durationSeconds = 450, avgHeartRate = 161) },
            ),
            // ⑥ 시즌 경계 — 직전 연도 마지막 순간(미포함) / 해당 연도 첫 순간(포함)
            MatchSpec(
                playedAt = "2025-12-31T23:59:59Z", totalDistanceM = 9999, result = MatchResultType.WIN,
                quarters = List(4) { QuarterSpec(durationSeconds = 900, avgHeartRate = 111) },
            ),
            MatchSpec(
                playedAt = "2026-01-01T00:00:00Z", totalDistanceM = 1234, goals = 1, assists = 0,
                maxSpeedKmh = 20.1, sprintCount = 1, result = MatchResultType.WIN,
                quarters = listOf(QuarterSpec(durationSeconds = 300, avgHeartRate = 140)),
            ),
            // ⑦ 시즌 밖 — 다음 연도 첫 순간(미포함)
            MatchSpec(
                playedAt = "2027-01-01T00:00:00Z", totalDistanceM = 8888, result = MatchResultType.WIN,
                quarters = List(3) { QuarterSpec(durationSeconds = 900, avgHeartRate = 177) },
            ),
        )
        specs.forEach { saveToBothStores(userId, it) }
        // ⑧ 타 사용자 경기 — 두 구현 모두 격리해야 한다
        saveToBothStores(
            otherUserId,
            MatchSpec(
                playedAt = "2026-04-01T09:00:00Z", totalDistanceM = 99999, goals = 9, assists = 9,
                maxSpeedKmh = 34.9, sprintCount = 99, result = MatchResultType.WIN,
                quarters = List(4) { QuarterSpec(durationSeconds = 900, avgHeartRate = 200) },
            ),
        )

        val fromInMemory = inMemoryService.getMySeasonStat(userId, 2026)
        val fromJpa = jpaService.getMySeasonStat(userId, 2026)

        assertEquals(fromInMemory, fromJpa)
        // 동등성만 보면 "둘 다 같이 틀린" 경우를 놓친다 — 핵심 값은 절대값으로도 고정한다.
        assertEquals(6, fromInMemory.matchCount)
        assertEquals(22734, fromInMemory.totalDistanceM)   // 5000+7000+3000+4000+2500+1234
        assertEquals(9, fromInMemory.quarterCount)         // 3+0+2+1+2+1 (시즌 밖 경기·타 사용자 제외)
        assertEquals(3, fromInMemory.winCount)
        assertEquals(1, fromInMemory.drawCount)
        assertEquals(2, fromInMemory.lossCount)
        // 가중합 671833 / 총 duration 4501 = 149.26... → 149 (버림)
        assertEquals(149, fromInMemory.avgHeartRate)
        assertEquals(31.2, fromInMemory.best.maxSpeedKmh)
        assertEquals(7000, fromInMemory.best.longestMatchDistanceM)
        assertEquals(19, fromInMemory.best.mostSprintCount)
        assertEquals(6500, fromInMemory.monthlyDistanceM[11])  // 12월 = 4000 + 2500
        assertEquals(1234, fromInMemory.monthlyDistanceM[0])   // 1월
    }

    @Test
    fun `모든 쿼터의 durationSeconds 가 0 인 시즌에서 두 구현 모두 avgHeartRate 0 을 낸다`() {
        saveToBothStores(
            userId,
            MatchSpec(
                playedAt = "2026-02-01T09:00:00Z", totalDistanceM = 1000, result = MatchResultType.WIN,
                quarters = List(2) { QuarterSpec(durationSeconds = 0, avgHeartRate = 175) },
            ),
        )

        val fromInMemory = inMemoryService.getMySeasonStat(userId, 2026)
        val fromJpa = jpaService.getMySeasonStat(userId, 2026)

        assertEquals(fromInMemory, fromJpa)
        assertEquals(0, fromJpa.avgHeartRate)
        assertEquals(2, fromJpa.quarterCount)
    }

    @Test
    fun `경기가 0건인 시즌에서 두 구현 모두 0 값 통계를 낸다`() {
        val fromInMemory = inMemoryService.getMySeasonStat(userId, 2024)
        val fromJpa = jpaService.getMySeasonStat(userId, 2024)

        assertEquals(fromInMemory, fromJpa)
        assertEquals(0, fromJpa.totalDistanceM)
        assertEquals(0, fromJpa.matchCount)
        assertEquals(0, fromJpa.quarterCount)
        assertEquals(0, fromJpa.avgHeartRate)
        assertEquals(0.0, fromJpa.best.maxSpeedKmh)
        assertEquals(List(12) { 0 }, fromJpa.monthlyDistanceM)
    }

    // MARK: - 헬퍼

    // 같은 사양으로 엔티티를 두 번 만들어 각 저장소에 넣는다.
    // JPA 에 저장된 managed 엔티티를 인메모리에 재사용하면 비교가 오염되므로 인스턴스를 공유하지 않는다.
    private fun saveToBothStores(ownerId: Long, spec: MatchSpec) {
        matchRepository.save(SeasonAggregateFixtures.match(ownerId, venueId, spec))
        inMemoryMatchRepository.save(SeasonAggregateFixtures.match(ownerId, venueId, spec))
    }

    private fun saveUser(): Long {
        return userRepository.save(
            User.create(displayName = "동등성사용자-${UUID.randomUUID()}", email = null),
        ).id
    }

    private fun saveVenue(): Long {
        return venueRepository.save(
            Venue.create(
                userId = userId,
                name = "동등성운동장-${UUID.randomUUID()}",
                geoLat = BigDecimal("37.6681"),
                geoLng = BigDecimal("126.7992"),
                address = null,
                roadAddress = null,
                provider = "kakao",
                providerPlaceId = UUID.randomUUID().toString(),
            ),
        ).id
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
