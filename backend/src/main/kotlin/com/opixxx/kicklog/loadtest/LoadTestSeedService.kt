package com.opixxx.kicklog.loadtest

import com.opixxx.kicklog.match.service.MatchResultType
import org.slf4j.LoggerFactory
import org.springframework.context.annotation.Profile
import org.springframework.jdbc.core.JdbcTemplate
import org.springframework.stereotype.Service
import org.springframework.transaction.annotation.Transactional
import java.sql.Timestamp
import java.time.Instant
import java.time.temporal.ChronoUnit
import java.util.UUID
import kotlin.random.Random

/**
 * 부하 테스트용 대량 시드 — `loadtest` 프로파일에서만 등록된다 (prod 미존재).
 *
 * JPA 영속성 컨텍스트 오버헤드를 피하려고 [JdbcTemplate] raw batch INSERT 로 수십만 행을 만든다.
 * 생성한 PK 는 "시드 직전 max(id) 보다 큰 id" 로 회수한다 — **단일 시드 호출 전제**
 * (부하테스트는 환경 구축 시 1회 시드하므로 동시 호출을 가정하지 않는다. 어긋나면 require 로 즉시 실패).
 *
 * `matches.result` 는 Aggregate invariant 와 동일하게 [MatchResultType.derive] 로 채운다.
 * `venue_id` 는 V8 에서 nullable 이 되었으므로 NULL 로 둔다 (venue 시드 불필요).
 */
@Service
@Profile("loadtest & !prod")
class LoadTestSeedService(
    private val jdbcTemplate: JdbcTemplate,
) {

    private val log = LoggerFactory.getLogger(javaClass)

    @Transactional
    fun seed(command: LoadTestSeedCommand): LoadTestResult {
        require(command.friendshipsPerUser == 0) {
            "friendshipsPerUser>0 시드는 아직 미구현입니다 (GET /friendships 부하 측정 시 후속 추가)"
        }
        // 동시 seed 호출을 직렬화한다 — 트랜잭션 스코프 advisory lock(커밋/롤백 시 자동 해제).
        // "max(id) 이후 행 조회" 방식의 PK 회수가 동시 트랜잭션의 간섭 없이 정확하도록 보장한다.
        jdbcTemplate.execute("SELECT pg_advisory_xact_lock($SEED_ADVISORY_LOCK_KEY)")

        val now = Instant.now()
        val random = Random(now.toEpochMilli())

        // 1) users — display_name 은 활성 UNIQUE(V12) 라 run 태그로 고유값을 보장한다.
        val beforeMaxUserId = currentMaxId("users")
        val runTag = UUID.randomUUID().toString().take(8)
        val nowTs = Timestamp.from(now)
        batchInsert(USER_INSERT_SQL, command.userCount) { i ->
            arrayOf("lt-$runTag-$i", nowTs, nowTs)
        }
        val userIds = idsCreatedAfter("users", beforeMaxUserId)
        require(userIds.size == command.userCount) {
            "사용자 시드 행 수 불일치: expected=${command.userCount}, actual=${userIds.size} (동시 시드 호출 의심)"
        }

        // 2) matches — user 순서대로 평탄화. matchIds(ORDER BY id)·insert 순서가 일치한다(IDENTITY 순차 할당).
        val matchIds: List<Long>
        if (command.matchesPerUser > 0) {
            val beforeMaxMatchId = currentMaxId("matches")
            val totalMatches = command.userCount * command.matchesPerUser
            batchInsert(MATCH_INSERT_SQL, totalMatches) { idx ->
                buildMatchArgs(userIds[idx / command.matchesPerUser], now, random)
            }
            matchIds = idsCreatedAfter("matches", beforeMaxMatchId)
            require(matchIds.size == totalMatches) {
                "매치 시드 행 수 불일치: expected=$totalMatches, actual=${matchIds.size} (동시 시드 호출 의심)"
            }
        } else {
            matchIds = emptyList()
        }

        // 3) quarter_workouts
        var quartersCreated = 0
        if (command.quartersPerMatch > 0 && matchIds.isNotEmpty()) {
            val totalQuarters = matchIds.size * command.quartersPerMatch
            batchInsert(QUARTER_INSERT_SQL, totalQuarters) { idx ->
                buildQuarterArgs(
                    matchId = matchIds[idx / command.quartersPerMatch],
                    quarterNumber = idx % command.quartersPerMatch + 1,
                    now = now,
                    random = random,
                )
            }
            quartersCreated = totalQuarters
        }

        log.info(
            "부하 시드 완료: users={}, matches={}, quarters={} (userId {}~{})",
            userIds.size,
            matchIds.size,
            quartersCreated,
            userIds.first(),
            userIds.last(),
        )

        // friendshipsPerUser>0 시드는 후속 작업 (GET /friendships 부하 측정 시 보강) — 현재는 0.
        return LoadTestResult(
            usersCreated = userIds.size,
            matchesCreated = matchIds.size,
            quartersCreated = quartersCreated,
            friendshipsCreated = 0,
            seededUserIdFrom = userIds.first(),
            seededUserIdTo = userIds.last(),
        )
    }

    private fun buildMatchArgs(userId: Long, now: Instant, random: Random): Array<Any> {
        val goals = random.nextInt(0, 4)
        val teamGoals = goals + random.nextInt(0, 3) // CHECK: team_goals >= goals, >= 0 보장
        val opponentGoals = random.nextInt(0, 5)
        val playedAt = now.minus(random.nextLong(0, SEED_SPAN_DAYS), ChronoUnit.DAYS)
        // team/opponent 를 항상 채우므로 result 는 non-null (invariant: result == derive(team, opp)).
        val result = MatchResultType.derive(teamGoals, opponentGoals)?.name
            ?: error("team/opponent goals 가 모두 설정되어 result 는 non-null 이어야 한다")
        return arrayOf(
            userId,
            UUID.randomUUID(), // client_match_id (UNIQUE per user)
            Timestamp.from(playedAt),
            "상대팀",
            result,
            goals,
            random.nextInt(0, 4), // assists
            opponentGoals,
            teamGoals,
            random.nextInt(3000, 9000), // total_distance_m
            random.nextDouble(15.0, 32.0), // max_speed_kmh
            random.nextInt(5, 40), // sprint_count
            random.nextInt(120, 176), // avg_heart_rate
            Timestamp.from(now), // created_at
            Timestamp.from(now), // updated_at
        )
    }

    private fun buildQuarterArgs(matchId: Long, quarterNumber: Int, now: Instant, random: Random): Array<Any> {
        val startedAt = now.minus(random.nextLong(0, SEED_SPAN_DAYS), ChronoUnit.DAYS)
        val durationSeconds = random.nextInt(600, 1500)
        return arrayOf(
            matchId,
            quarterNumber,
            UUID.randomUUID().toString(), // health_kit_workout_id
            Timestamp.from(startedAt),
            Timestamp.from(startedAt.plusSeconds(durationSeconds.toLong())),
            durationSeconds,
            random.nextInt(800, 2500), // distance_m
            random.nextDouble(6.0, 12.0), // avg_speed_kmh
            random.nextDouble(15.0, 32.0), // max_speed_kmh
            random.nextInt(120, 176), // avg_heart_rate
            random.nextInt(170, 195), // max_heart_rate
            random.nextInt(1, 12), // sprint_count
            random.nextInt(80, 320), // active_energy_kcal
        )
    }

    private fun currentMaxId(table: String): Long =
        jdbcTemplate.queryForObject("SELECT COALESCE(MAX(id), 0) FROM $table", Long::class.java) ?: 0L

    private fun idsCreatedAfter(table: String, afterId: Long): List<Long> =
        jdbcTemplate.queryForList(
            "SELECT id FROM $table WHERE id > ? ORDER BY id",
            Long::class.java,
            afterId,
        )

    /** [total] 건을 [BATCH_SIZE] 청크로 나눠 batch INSERT 한다 (대량 행의 메모리 부담 완화). */
    private fun batchInsert(sql: String, total: Int, args: (Int) -> Array<Any>) {
        var start = 0
        while (start < total) {
            val end = minOf(start + BATCH_SIZE, total)
            val batchArgs = (start until end).map(args)
            jdbcTemplate.batchUpdate(sql, batchArgs)
            start = end
        }
    }

    companion object {
        private const val BATCH_SIZE = 1_000
        private const val SEED_SPAN_DAYS = 730L // 최근 2년에 분산 — 시즌/월별 집계가 의미 있게 동작하도록

        // 동시 seed 호출 직렬화용 advisory lock 키 (loadtest 하네스 전용 고정값).
        private const val SEED_ADVISORY_LOCK_KEY = 990306L

        private const val USER_INSERT_SQL =
            "INSERT INTO users (display_name, created_at, updated_at) VALUES (?, ?, ?)"

        private val MATCH_INSERT_SQL = """
            INSERT INTO matches (
                user_id, client_match_id, venue_id, played_at, opponent, result, position,
                goals, assists, opponent_goals, team_goals,
                total_distance_m, max_speed_kmh, sprint_count, avg_heart_rate,
                created_at, updated_at
            ) VALUES (?, ?, NULL, ?, ?, ?, NULL, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """.trimIndent()

        private val QUARTER_INSERT_SQL = """
            INSERT INTO quarter_workouts (
                match_id, quarter_number, health_kit_workout_id, started_at, ended_at,
                duration_seconds, distance_m, avg_speed_kmh, max_speed_kmh,
                avg_heart_rate, max_heart_rate, sprint_count, active_energy_kcal
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """.trimIndent()
    }
}
