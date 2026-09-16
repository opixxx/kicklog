package com.opixxx.kicklog.stat

import com.opixxx.kicklog.common.security.JwtTokenProvider
import com.opixxx.kicklog.user.entity.User
import com.opixxx.kicklog.user.repository.UserRepository
import org.junit.jupiter.api.Test
import org.springframework.beans.factory.annotation.Autowired
import org.springframework.boot.test.context.SpringBootTest
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc
import org.springframework.http.HttpHeaders
import org.springframework.http.MediaType
import org.springframework.test.context.ActiveProfiles
import org.springframework.test.web.servlet.MockMvc
import org.springframework.test.web.servlet.get
import org.springframework.test.web.servlet.post
import org.springframework.test.web.servlet.put
import java.util.UUID

/**
 * EXEC_PLAN 2026-09-16 season-stat-sql-aggregation (3-A) — 시즌 통계 집계 인수 시나리오.
 *
 * 본 작업은 **동작 보존 리팩토링**이다. 이 파일은 "메모리 집계 → DB 집계 SQL" 전환 전후로
 * **API 응답 숫자가 1도 바뀌지 않음**을 고정하는 특성화(characterization) 안전망이다.
 * 따라서 전환 전에도 GREEN 이고, 전환 후에도 GREEN 이어야 한다.
 *
 * 기존 [SeasonStatAcceptanceTest] 가 못 잡는 두 함정을 정면으로 겨냥한다.
 * 1. **fan-out 중복 합산** — 기존 테스트는 경기당 쿼터가 1개뿐이라 matches ⨝ quarter_workouts
 *    조인 집계로 경기 지표가 쿼터 개수배로 부풀어도 통과한다. 여기서는 경기당 쿼터 3개를 쓴다.
 * 2. **UTC 월 경계** — 기존 테스트의 `2026-12-31T09:00:00Z` 는 KST 로도 12/31 이라 경계가 안 걸린다.
 *    여기서는 `2026-12-31T15:00:00Z` (KST 로는 2027-01-01) 를 쓴다. api-spec §8.1 이
 *    "UTC playedAt.month 기준" 으로 못 박았으므로 서버 TZ 와 무관하게 12월이어야 한다.
 */
@SpringBootTest
@AutoConfigureMockMvc
@ActiveProfiles("test")
class SeasonStatAggregationAcceptanceTest {

    @Autowired
    private lateinit var mockMvc: MockMvc

    @Autowired
    private lateinit var jwtTokenProvider: JwtTokenProvider

    @Autowired
    private lateinit var userRepository: UserRepository

    @Test
    fun `쿼터가 여러 개인 경기들의 시즌 통계는 경기 지표를 중복 합산하지 않는다`() {
        val token = jwtTokenProvider.createAccessToken(userId = 301L)
        val venueId = createVenue(token, "팬아웃운동장")
        // 경기 2건 × 쿼터 3개. 조인 집계로 fan-out 되면 totalDistanceM 이 12000 이 아니라 36000 이 된다.
        saveMatch(
            token, venueId,
            playedAt = "2026-03-01T09:00:00Z", totalDistanceM = 5000, goals = 2, assists = 1,
            sprintCount = 11, maxSpeedKmh = 29.4, quarterHeartRates = listOf(150, 150, 150),
        )
        saveMatch(
            token, venueId,
            playedAt = "2026-05-01T09:00:00Z", totalDistanceM = 7000, goals = 1, assists = 2,
            sprintCount = 17, maxSpeedKmh = 26.0, quarterHeartRates = listOf(120, 120, 120),
        )

        mockMvc.get("/users/me/seasons/2026") {
            header(HttpHeaders.AUTHORIZATION, "Bearer $token")
        }.andExpect {
            status { isOk() }
            // 경기 단위 지표 — 쿼터 수(3)와 무관하게 1회씩만 합산되어야 한다.
            jsonPath("$.totalDistanceM") { value(12000) }
            jsonPath("$.totalGoals") { value(3) }
            jsonPath("$.totalAssists") { value(3) }
            jsonPath("$.matchCount") { value(2) }
            jsonPath("$.winCount") { value(2) }
            // 쿼터 단위 지표 — 이쪽은 6개가 맞다.
            jsonPath("$.quarterCount") { value(6) }
            // 가중평균 심박 = (3*900*150 + 3*900*120) / 5400 = 135
            jsonPath("$.avgHeartRate") { value(135) }
            // best 는 MAX 라 fan-out 이 있어도 안 변한다 — 경계값 고정 목적으로만 검증.
            jsonPath("$.best.maxSpeedKmh") { value(29.4) }
            jsonPath("$.best.longestMatchDistanceM") { value(7000) }
            jsonPath("$.best.mostSprintCount") { value(17) }
            // 3월(index 2) 5000, 5월(index 4) 7000 — 월별도 중복 합산되면 안 된다.
            jsonPath("$.monthlyDistanceM[2]") { value(5000) }
            jsonPath("$.monthlyDistanceM[4]") { value(7000) }
        }
    }

    @Test
    fun `UTC 기준 12월 말 경기는 해당 연도 12월에 집계된다`() {
        val token = jwtTokenProvider.createAccessToken(userId = 302L)
        val venueId = createVenue(token, "월경계운동장")
        // KST(UTC+9) 로는 2027-01-01 06:00. UTC 기준이므로 2026년 12월이어야 한다.
        saveMatch(
            token, venueId,
            playedAt = "2026-12-31T15:00:00Z", totalDistanceM = 4000, goals = 0, assists = 0,
            sprintCount = 3, maxSpeedKmh = 20.0, quarterHeartRates = listOf(140),
        )

        mockMvc.get("/users/me/seasons/2026") {
            header(HttpHeaders.AUTHORIZATION, "Bearer $token")
        }.andExpect {
            status { isOk() }
            jsonPath("$.matchCount") { value(1) }
            jsonPath("$.totalDistanceM") { value(4000) }
            jsonPath("$.monthlyDistanceM[11]") { value(4000) }   // 12월
            jsonPath("$.monthlyDistanceM[0]") { value(0) }       // 1월로 새지 않는다
        }
    }

    @Test
    fun `UTC 기준 12월 말 경기는 다음 연도 통계에 포함되지 않는다`() {
        val token = jwtTokenProvider.createAccessToken(userId = 303L)
        val venueId = createVenue(token, "월경계다음해운동장")
        saveMatch(
            token, venueId,
            playedAt = "2026-12-31T15:00:00Z", totalDistanceM = 4000, goals = 0, assists = 0,
            sprintCount = 3, maxSpeedKmh = 20.0, quarterHeartRates = listOf(140),
        )

        mockMvc.get("/users/me/seasons/2027") {
            header(HttpHeaders.AUTHORIZATION, "Bearer $token")
        }.andExpect {
            status { isOk() }
            jsonPath("$.matchCount") { value(0) }
            jsonPath("$.totalDistanceM") { value(0) }
            jsonPath("$.quarterCount") { value(0) }
        }
    }

    @Test
    fun `친구가 아니면 시즌 통계를 조회할 수 없다`() {
        val viewer = createUser("집계비친구조회자")
        val other = createUser("집계비친구대상")
        val viewerToken = jwtTokenProvider.createAccessToken(viewer.id)

        mockMvc.get("/users/${other.id}/seasons/2026") {
            header(HttpHeaders.AUTHORIZATION, "Bearer $viewerToken")
        }.andExpect {
            status { isForbidden() }
            jsonPath("$.code") { value("FRIEND_UNAUTHORIZED") }
        }
    }

    // MARK: - 헬퍼

    private fun createUser(displayName: String): User {
        return userRepository.save(User.create(displayName = displayName, email = "$displayName@example.com"))
    }

    private fun createVenue(accessToken: String, name: String): Long {
        val response = mockMvc.post("/venues") {
            header(HttpHeaders.AUTHORIZATION, "Bearer $accessToken")
            contentType = MediaType.APPLICATION_JSON
            content = """
                {
                  "name": "$name",
                  "geoLat": 37.668100,
                  "geoLng": 126.799200,
                  "provider": "kakao",
                  "providerPlaceId": "$name"
                }
            """.trimIndent()
        }.andReturn().response.contentAsString

        return Regex(""""id":(\d+)""").find(response)!!.groupValues[1].toLong()
    }

    private fun saveMatch(
        accessToken: String,
        venueId: Long,
        playedAt: String,
        totalDistanceM: Int,
        goals: Int,
        assists: Int,
        sprintCount: Int,
        maxSpeedKmh: Double,
        quarterHeartRates: List<Int>,
    ) {
        val clientMatchId = UUID.randomUUID()
        mockMvc.put("/matches/$clientMatchId") {
            header(HttpHeaders.AUTHORIZATION, "Bearer $accessToken")
            contentType = MediaType.APPLICATION_JSON
            content = matchJson(
                clientMatchId = clientMatchId,
                venueId = venueId,
                playedAt = playedAt,
                totalDistanceM = totalDistanceM,
                goals = goals,
                assists = assists,
                sprintCount = sprintCount,
                maxSpeedKmh = maxSpeedKmh,
                quarterHeartRates = quarterHeartRates,
            )
        }.andExpect {
            status { isCreated() }
        }
    }

    private fun matchJson(
        clientMatchId: UUID,
        venueId: Long,
        playedAt: String,
        totalDistanceM: Int,
        goals: Int,
        assists: Int,
        sprintCount: Int,
        maxSpeedKmh: Double,
        quarterHeartRates: List<Int>,
    ): String {
        // 모든 쿼터 durationSeconds 를 900 으로 고정해 가중평균 심박을 단순 평균으로 계산 가능하게 한다.
        val quarters = quarterHeartRates.mapIndexed { index, heartRate ->
            """
            {
              "quarterNumber": ${index + 1},
              "healthKitWorkoutId": "hk-$clientMatchId-${index + 1}",
              "startedAt": "$playedAt",
              "endedAt": "$playedAt",
              "durationSeconds": 900,
              "distanceM": ${totalDistanceM / quarterHeartRates.size},
              "avgSpeedKmh": 6.1,
              "maxSpeedKmh": $maxSpeedKmh,
              "avgHeartRate": $heartRate,
              "maxHeartRate": ${heartRate + 10},
              "sprintCount": $sprintCount,
              "activeEnergyKcal": 120
            }
            """.trimIndent()
        }.joinToString(",")

        return """
            {
              "venueId": $venueId,
              "playedAt": "$playedAt",
              "opponent": "OO FC",
              "position": "MF",
              "goals": $goals,
              "assists": $assists,
              "teamGoals": ${maxOf(goals, 1)},
              "opponentGoals": 0,
              "totalDistanceM": $totalDistanceM,
              "maxSpeedKmh": $maxSpeedKmh,
              "sprintCount": $sprintCount,
              "avgHeartRate": 151,
              "quarters": [$quarters]
            }
        """.trimIndent()
    }
}
