package com.opixxx.kicklog.match.repository

import com.opixxx.kicklog.friend.KickLogPostgresContainer
import com.opixxx.kicklog.match.entity.Match
import com.opixxx.kicklog.match.service.UpsertMatchCommand
import com.opixxx.kicklog.match.service.UpsertQuarterCommand
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
import kotlin.test.Test
import kotlin.test.assertEquals

/**
 * EXEC_PLAN 2026-06-10 audit-fixes P1-1 — Match.quarters N+1 제거 (fetch join).
 *
 * findAllByUserIdAndPlayedAtBetween 에 JOIN FETCH m.quarters 가 적용되면
 * 반환된 Match 가 트랜잭션 밖(detached)에서도 quarters 를 초기화된 상태로 들고 있어
 * LazyInitializationException 없이 접근할 수 있다.
 *
 * 본 테스트는 @Transactional 을 의도적으로 붙이지 않아, repository 호출 직후 영속성 컨텍스트가
 * 닫힌 detached 상태에서 quarters 에 접근한다. 현재(fetch join 미적용 + onEach 강제 초기화) 코드는
 * 영속성 컨텍스트 밖이므로 LazyInitializationException 으로 실패해야 한다(RED).
 * Testcontainers 실 PostgreSQL + flyway 로 검증한다.
 */
@SpringBootTest(
    properties = [
        "spring.flyway.enabled=true",
        "spring.jpa.hibernate.ddl-auto=validate",
        // OSIV 가 켜지면 detached 검증이 무력화되므로 명시적으로 끈다.
        "spring.jpa.open-in-view=false",
    ],
)
@Testcontainers(disabledWithoutDocker = true)
class MatchQuartersFetchJoinIntegrationTest {

    @Autowired
    private lateinit var matchRepository: MatchRepository

    @Autowired
    private lateinit var venueRepository: VenueRepository

    @Autowired
    private lateinit var userRepository: UserRepository

    // venues/matches 는 users(id) FK 를 가지므로 실제 사용자 row 를 먼저 만들고 그 id 를 쓴다.
    private var userId: Long = 0L

    private val seasonStart: Instant = Instant.parse("2026-01-01T00:00:00Z")
    private val seasonEnd: Instant = Instant.parse("2027-01-01T00:00:00Z")

    @kotlin.test.BeforeTest
    fun setUp() {
        userId = userRepository.save(
            User.create(displayName = "fetchjoin사용자-${UUID.randomUUID()}", email = null),
        ).id
    }

    @Test
    fun `fetch join 으로 조회하면 트랜잭션 밖에서 quarters 에 접근해도 LazyInitializationException 이 발생하지 않는다`() {
        val venueId = saveVenue()
        saveMatchWithQuarters(venueId, "2026-03-01T09:00:00Z", quarterCount = 2)
        saveMatchWithQuarters(venueId, "2026-05-01T09:00:00Z", quarterCount = 3)

        val matches = matchRepository.findAllByUserIdAndPlayedAtBetween(userId, seasonStart, seasonEnd)

        // 영속성 컨텍스트 밖(detached)에서 quarters 접근 — fetch join 이면 예외 없이 size 가 읽힌다.
        val totalQuarters = matches.sumOf { it.quarters.size }
        assertEquals(5, totalQuarters)
    }

    @Test
    fun `fetch join 조회 결과는 playedAt DESC, id DESC 정렬을 유지한다`() {
        val venueId = saveVenue()
        saveMatchWithQuarters(venueId, "2026-03-01T09:00:00Z", quarterCount = 1)
        saveMatchWithQuarters(venueId, "2026-05-01T09:00:00Z", quarterCount = 1)
        saveMatchWithQuarters(venueId, "2026-04-01T09:00:00Z", quarterCount = 1)

        val matches = matchRepository.findAllByUserIdAndPlayedAtBetween(userId, seasonStart, seasonEnd)

        val playedAtOrder = matches.map { it.playedAt }
        assertEquals(playedAtOrder.sortedDescending(), playedAtOrder)
    }

    private fun saveVenue(): Long {
        val venue = venueRepository.save(
            Venue.create(
                userId = userId,
                name = "fetchjoin-${UUID.randomUUID()}",
                geoLat = BigDecimal("37.6681"),
                geoLng = BigDecimal("126.7992"),
                address = null,
                roadAddress = null,
                provider = "kakao",
                providerPlaceId = UUID.randomUUID().toString(),
            ),
        )
        return venue.id
    }

    private fun saveMatchWithQuarters(venueId: Long, playedAt: String, quarterCount: Int) {
        val played = Instant.parse(playedAt)
        val quarters = (1..quarterCount).map { n ->
            UpsertQuarterCommand(
                quarterNumber = n,
                healthKitWorkoutId = "hk-${UUID.randomUUID()}",
                startedAt = played,
                endedAt = played.plusSeconds(900),
                durationSeconds = 900,
                distanceM = 1000,
            )
        }
        val command = UpsertMatchCommand(
            venueId = venueId,
            playedAt = played,
            opponent = "OO FC",
            position = null,
            goals = 0,
            assists = 0,
            quarters = quarters,
            teamGoals = 1,
            opponentGoals = 0,
            totalDistanceM = 1000,
        )
        matchRepository.save(Match.create(userId, UUID.randomUUID(), command))
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
