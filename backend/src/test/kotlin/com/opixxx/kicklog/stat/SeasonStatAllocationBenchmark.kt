package com.opixxx.kicklog.stat

import com.opixxx.kicklog.friend.KickLogPostgresContainer
import com.opixxx.kicklog.match.repository.MatchRepository
import com.opixxx.kicklog.stat.service.SeasonStatService
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
import org.junit.jupiter.api.Disabled
import org.testcontainers.junit.jupiter.Testcontainers
import java.lang.management.ManagementFactory
import java.math.BigDecimal
import java.util.UUID
import kotlin.test.BeforeTest
import kotlin.test.Test

/**
 * 시즌 통계 조회의 **호출당 힙 할당량**을 측정한다. 성능 비교용이며 단정(assert)이 없다.
 *
 * EXPLAIN 실측(2026-09-16)에서 DB 실행 시간은 두 구현이 사실상 동일했다(12.7ms vs 12.1ms).
 * 즉 이 리팩토링의 근거는 DB 가 아니라 **애플리케이션 측 할당·GC** 에 있어야 한다.
 * 그걸 확인하지 않으면 "왜 바꿨나" 에 답할 수 없다.
 *
 * JFR 대신 `ThreadMXBean.getThreadAllocatedBytes` 를 쓴다 — 샘플링이 아니라 스레드 누적
 * 할당 바이트를 직접 읽으므로 호출당 정확한 값이 나온다.
 *
 * 같은 파일을 기존 구현(메모리 집계) 브랜치에 그대로 넣어 실행하면 A/B 비교가 된다
 * (양쪽 모두 `SeasonStatService.getMySeasonStat` 만 호출하므로 측정 코드는 동일하다).
 */
@SpringBootTest(
    properties = [
        "spring.flyway.enabled=true",
        "spring.jpa.hibernate.ddl-auto=validate",
        "spring.jpa.open-in-view=false",
    ],
)
@Testcontainers(disabledWithoutDocker = true)
@Disabled(
    "측정 전용 — CI 에서 매번 돌리면 경기 300건 시드 + 1,200회 호출로 빌드가 느려진다. " +
    "수동 실행: DOCKER_HOST=unix://\$HOME/.colima/default/docker.sock " +
    "TESTCONTAINERS_DOCKER_SOCKET_OVERRIDE=/var/run/docker.sock " +
    "./gradlew test --tests '*SeasonStatAllocationBenchmark*' -i",
)
class SeasonStatAllocationBenchmark {

    @Autowired private lateinit var seasonStatService: SeasonStatService
    @Autowired private lateinit var matchRepository: MatchRepository
    @Autowired private lateinit var venueRepository: VenueRepository
    @Autowired private lateinit var userRepository: UserRepository

    private var userId: Long = 0L

    companion object {
        private const val MATCH_COUNT = 300        // ADR-0011 기준 사용자당 경기 수
        private const val QUARTERS_PER_MATCH = 4
        private const val WARMUP = 200             // JIT 컴파일 안정화
        private const val MEASURE = 1_000

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
    fun seed() {
        userId = userRepository.save(
            User.create(displayName = "벤치-${UUID.randomUUID()}", email = null),
        ).id
        val venueId = venueRepository.save(
            Venue.create(
                userId = userId,
                name = "벤치운동장-${UUID.randomUUID()}",
                geoLat = BigDecimal("37.6681"),
                geoLng = BigDecimal("126.7992"),
                address = null,
                roadAddress = null,
                provider = "kakao",
                providerPlaceId = UUID.randomUUID().toString(),
            ),
        ).id
        repeat(MATCH_COUNT) { i ->
            matchRepository.save(
                SeasonAggregateFixtures.match(
                    userId, venueId,
                    MatchSpec(
                        // 1년에 고르게 분포 (월별 집계가 12개 그룹을 모두 타도록)
                        playedAt = "2026-%02d-%02dT09:00:00Z".format((i % 12) + 1, (i % 28) + 1),
                        totalDistanceM = 4000 + i,
                        goals = i % 4,
                        assists = i % 3,
                        maxSpeedKmh = 25.0 + (i % 10),
                        sprintCount = i % 20,
                        quarters = List(QUARTERS_PER_MATCH) {
                            QuarterSpec(durationSeconds = 900, avgHeartRate = 140 + (i % 30))
                        },
                    ),
                ),
            )
        }
    }

    @Test
    fun `시즌 통계 조회의 호출당 할당량과 GC 부하를 측정한다`() {
        val threadBean = ManagementFactory.getThreadMXBean() as com.sun.management.ThreadMXBean
        val tid = Thread.currentThread().id

        repeat(WARMUP) { seasonStatService.getMySeasonStat(userId, 2026) }

        System.gc()
        Thread.sleep(500)

        val gcCountBefore = gcCount()
        val gcTimeBefore = gcTime()
        val allocBefore = threadBean.getThreadAllocatedBytes(tid)
        val startNanos = System.nanoTime()

        repeat(MEASURE) { seasonStatService.getMySeasonStat(userId, 2026) }

        val elapsedMs = (System.nanoTime() - startNanos) / 1_000_000.0
        val allocatedBytes = threadBean.getThreadAllocatedBytes(tid) - allocBefore
        val gcCountDelta = gcCount() - gcCountBefore
        val gcTimeDelta = gcTime() - gcTimeBefore

        println(
            """
            |
            |╔══════════════════════════════════════════════════════════════╗
            |║  시즌 통계 할당량 측정                                        ║
            |╠══════════════════════════════════════════════════════════════╣
            |║  시드      : 경기 $MATCH_COUNT 건 × 쿼터 $QUARTERS_PER_MATCH 개 = 쿼터 ${MATCH_COUNT * QUARTERS_PER_MATCH} 개
            |║  호출      : warm-up $WARMUP + 측정 $MEASURE
            |╟──────────────────────────────────────────────────────────────╢
            |║  총 할당    : ${"%,d".format(allocatedBytes)} bytes (${"%.1f".format(allocatedBytes / 1024.0 / 1024.0)} MB)
            |║  호출당 할당: ${"%,d".format(allocatedBytes / MEASURE)} bytes (${"%.1f".format(allocatedBytes / MEASURE / 1024.0)} KB)
            |║  총 시간    : ${"%.1f".format(elapsedMs)} ms
            |║  호출당 시간: ${"%.3f".format(elapsedMs / MEASURE)} ms
            |║  GC 횟수    : $gcCountDelta
            |║  GC 시간    : $gcTimeDelta ms
            |╚══════════════════════════════════════════════════════════════╝
            """.trimMargin(),
        )
    }

    private fun gcCount(): Long =
        ManagementFactory.getGarbageCollectorMXBeans().sumOf { maxOf(it.collectionCount, 0L) }

    private fun gcTime(): Long =
        ManagementFactory.getGarbageCollectorMXBeans().sumOf { maxOf(it.collectionTime, 0L) }
}
