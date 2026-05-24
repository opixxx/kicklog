package com.opixxx.kicklog.stat

import com.opixxx.kicklog.common.security.JwtTokenProvider
import com.opixxx.kicklog.friend.entity.Friendship
import com.opixxx.kicklog.friend.repository.FriendshipRepository
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
import java.time.Instant

@SpringBootTest
@AutoConfigureMockMvc
@ActiveProfiles("test")
class SeasonStatAcceptanceTest {

    @Autowired
    private lateinit var mockMvc: MockMvc

    @Autowired
    private lateinit var jwtTokenProvider: JwtTokenProvider

    @Autowired
    private lateinit var userRepository: UserRepository

    @Autowired
    private lateinit var friendshipRepository: FriendshipRepository

    @Test
    fun `로그인 사용자는 본인 시즌 통계를 조회한다`() {
        val token = jwtTokenProvider.createAccessToken(userId = 101L)
        val venueId = createVenue(token, "시즌본인운동장")
        saveMetricMatch(token, "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa1", venueId, "2026-03-01T09:00:00Z", 6000, 2, 1, 11)
        saveMetricMatch(token, "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa2", venueId, "2026-05-01T09:00:00Z", 8200, 1, 2, 17)
        saveMetricMatch(token, "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa3", venueId, "2025-05-01T09:00:00Z", 9000, 9, 9, 30)

        mockMvc.get("/users/me/seasons/2026") {
            header(HttpHeaders.AUTHORIZATION, "Bearer $token")
        }.andExpect {
            status { isOk() }
            jsonPath("$.year") { value(2026) }
            jsonPath("$.totalDistanceM") { value(14200) }
            jsonPath("$.totalGoals") { value(3) }
            jsonPath("$.totalAssists") { value(3) }
            jsonPath("$.matchCount") { value(2) }
            jsonPath("$.quarterCount") { value(2) }
            jsonPath("$.best.maxSpeedKmh") { value(29.4) }
            jsonPath("$.best.longestMatchDistanceM") { value(8200) }
            jsonPath("$.best.mostSprintCount") { value(17) }
        }
    }

    @Test
    fun `경기 없는 연도도 0값 통계를 반환한다`() {
        val token = jwtTokenProvider.createAccessToken(userId = 102L)

        mockMvc.get("/users/me/seasons/2024") {
            header(HttpHeaders.AUTHORIZATION, "Bearer $token")
        }.andExpect {
            status { isOk() }
            jsonPath("$.totalDistanceM") { value(0) }
            jsonPath("$.matchCount") { value(0) }
            jsonPath("$.best.maxSpeedKmh") { value(0.0) }
        }
    }

    @Test
    fun `accepted 친구의 시즌 통계를 조회한다`() {
        val viewer = createUser("시즌조회자")
        val friend = createUser("시즌친구")
        val viewerToken = jwtTokenProvider.createAccessToken(viewer.id)
        val friendToken = jwtTokenProvider.createAccessToken(friend.id)
        saveAcceptedFriendship(viewer.id, friend.id)
        val venueId = createVenue(friendToken, "친구시즌운동장")
        saveMetricMatch(friendToken, "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbb1", venueId, "2026-04-01T09:00:00Z", 5100, 1, 0, 8)

        mockMvc.get("/users/${friend.id}/seasons/2026") {
            header(HttpHeaders.AUTHORIZATION, "Bearer $viewerToken")
        }.andExpect {
            status { isOk() }
            jsonPath("$.totalDistanceM") { value(5100) }
            jsonPath("$.matchCount") { value(1) }
        }
    }

    @Test
    fun `accepted 친구가 아니면 시즌 통계를 조회할 수 없다`() {
        val viewer = createUser("시즌비친구조회자")
        val other = createUser("시즌비친구대상")
        val viewerToken = jwtTokenProvider.createAccessToken(viewer.id)

        mockMvc.get("/users/${other.id}/seasons/2026") {
            header(HttpHeaders.AUTHORIZATION, "Bearer $viewerToken")
        }.andExpect {
            status { isForbidden() }
            jsonPath("$.code") { value("FRIEND_UNAUTHORIZED") }
        }
    }

    @Test
    fun `연도 범위를 벗어나면 거부한다`() {
        val token = jwtTokenProvider.createAccessToken(userId = 103L)

        mockMvc.get("/users/me/seasons/1999") {
            header(HttpHeaders.AUTHORIZATION, "Bearer $token")
        }.andExpect {
            status { isBadRequest() }
            jsonPath("$.code") { value("VALIDATION_FAILED") }
        }
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

    private fun saveMetricMatch(
        accessToken: String,
        clientMatchId: String,
        venueId: Long,
        playedAt: String,
        distance: Int,
        goals: Int,
        assists: Int,
        sprint: Int,
    ) {
        mockMvc.put("/matches/$clientMatchId") {
            header(HttpHeaders.AUTHORIZATION, "Bearer $accessToken")
            contentType = MediaType.APPLICATION_JSON
            content = metricMatchJson(venueId, playedAt, distance, goals, assists, sprint)
        }.andExpect {
            status { isCreated() }
        }
    }

    private fun metricMatchJson(venueId: Long, playedAt: String, distance: Int, goals: Int, assists: Int, sprint: Int): String {
        return """
            {
              "venueId": $venueId,
              "playedAt": "$playedAt",
              "opponent": "OO FC",
              "result": "WIN",
              "position": "MF",
              "goals": $goals,
              "assists": $assists,
              "totalDistanceM": $distance,
              "maxSpeedKmh": 29.4,
              "sprintCount": $sprint,
              "avgHeartRate": 151,
              "quarters": [
                {
                  "quarterNumber": 1,
                  "healthKitWorkoutId": "hk-$clientSafeDate-$distance",
                  "startedAt": "$playedAt",
                  "endedAt": "$playedAt",
                  "durationSeconds": 900,
                  "distanceM": $distance,
                  "avgSpeedKmh": 6.1,
                  "avgHeartRate": 145,
                  "maxHeartRate": 160,
                  "sprintCount": $sprint,
                  "activeEnergyKcal": 120
                }
              ]
            }
        """.trimIndent()
    }

    private val clientSafeDate: String = "20260524"

    private fun createUser(displayName: String): User {
        return userRepository.save(User.create(displayName = displayName, email = "$displayName@example.com"))
    }

    private fun saveAcceptedFriendship(userId: Long, targetUserId: Long) {
        val now = Instant.parse("2026-05-23T09:00:00Z")
        val friendship = Friendship.createPending(userId, targetUserId, now)
        friendship.accept(now)
        friendshipRepository.save(friendship)
    }
}
