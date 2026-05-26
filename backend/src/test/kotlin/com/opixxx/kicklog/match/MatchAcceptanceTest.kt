package com.opixxx.kicklog.match

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
import org.springframework.test.web.servlet.delete
import org.springframework.test.web.servlet.get
import org.springframework.test.web.servlet.post
import org.springframework.test.web.servlet.put
import java.time.Instant

@SpringBootTest
@AutoConfigureMockMvc
@ActiveProfiles("test")
class MatchAcceptanceTest {

    @Autowired
    private lateinit var mockMvc: MockMvc

    @Autowired
    private lateinit var jwtTokenProvider: JwtTokenProvider

    @Autowired
    private lateinit var userRepository: UserRepository

    @Autowired
    private lateinit var friendshipRepository: FriendshipRepository

    @Test
    fun `로그인 사용자는 경기와 쿼터를 저장하고 clientMatchId로 다시 조회한다`() {
        val accessToken = jwtTokenProvider.createAccessToken(userId = 1L)
        val venueId = createVenue(accessToken)
        val clientMatchId = "11111111-1111-1111-1111-111111111111"

        mockMvc.put("/matches/$clientMatchId") {
            header(HttpHeaders.AUTHORIZATION, "Bearer $accessToken")
            contentType = MediaType.APPLICATION_JSON
            content = matchJson(venueId = venueId)
        }.andExpect {
            status { isCreated() }
            jsonPath("$.clientMatchId") { value(clientMatchId) }
            jsonPath("$.venueId") { value(venueId) }
            jsonPath("$.opponent") { value("OO FC") }
            jsonPath("$.result") { value("WIN") }
            jsonPath("$.quarters[0].quarterNumber") { value(1) }
            jsonPath("$.quarters[0].healthKitWorkoutId") { value("hk-uuid-1") }
        }

        mockMvc.get("/matches/by-client-id/$clientMatchId") {
            header(HttpHeaders.AUTHORIZATION, "Bearer $accessToken")
        }.andExpect {
            status { isOk() }
            jsonPath("$.clientMatchId") { value(clientMatchId) }
            jsonPath("$.quarters.length()") { value(1) }
        }
    }

    @Test
    fun `같은 clientMatchId로 다시 저장하면 기존 경기를 덮어쓴다`() {
        val accessToken = jwtTokenProvider.createAccessToken(userId = 2L)
        val venueId = createVenue(accessToken, name = "두번째 운동장")
        val clientMatchId = "22222222-2222-2222-2222-222222222222"

        mockMvc.put("/matches/$clientMatchId") {
            header(HttpHeaders.AUTHORIZATION, "Bearer $accessToken")
            contentType = MediaType.APPLICATION_JSON
            content = matchJson(venueId = venueId, goals = 1, quarterWorkoutId = "hk-old")
        }.andExpect {
            status { isCreated() }
        }

        mockMvc.put("/matches/$clientMatchId") {
            header(HttpHeaders.AUTHORIZATION, "Bearer $accessToken")
            contentType = MediaType.APPLICATION_JSON
            content = matchJson(venueId = venueId, goals = 2, quarterWorkoutId = "hk-new")
        }.andExpect {
            status { isOk() }
            jsonPath("$.goals") { value(2) }
            jsonPath("$.quarters.length()") { value(1) }
            jsonPath("$.quarters[0].healthKitWorkoutId") { value("hk-new") }
        }
    }

    @Test
    fun `내 경기 목록은 최신순 cursor 방식으로 조회한다`() {
        val accessToken = jwtTokenProvider.createAccessToken(userId = 3L)
        val venueId = createVenue(accessToken, name = "목록 운동장")

        saveMatch(accessToken, "33333333-3333-3333-3333-333333333331", venueId, "2026-05-21T09:00:00Z")
        saveMatch(accessToken, "33333333-3333-3333-3333-333333333332", venueId, "2026-05-22T09:00:00Z")
        saveMatch(accessToken, "33333333-3333-3333-3333-333333333333", venueId, "2026-05-23T09:00:00Z")

        val firstPage = mockMvc.get("/matches") {
            header(HttpHeaders.AUTHORIZATION, "Bearer $accessToken")
            param("size", "2")
        }.andExpect {
            status { isOk() }
            jsonPath("$.content.length()") { value(2) }
            jsonPath("$.content[0].playedAt") { value("2026-05-23T09:00:00Z") }
            jsonPath("$.content[1].playedAt") { value("2026-05-22T09:00:00Z") }
            jsonPath("$.nextCursor") { isNotEmpty() }
            jsonPath("$.hasNext") { value(true) }
        }.andReturn().response.contentAsString

        val nextCursor = Regex(""""nextCursor":"([^"]+)"""").find(firstPage)!!.groupValues[1]

        mockMvc.get("/matches") {
            header(HttpHeaders.AUTHORIZATION, "Bearer $accessToken")
            param("size", "2")
            param("cursor", nextCursor)
        }.andExpect {
            status { isOk() }
            jsonPath("$.content.length()") { value(1) }
            jsonPath("$.content[0].playedAt") { value("2026-05-21T09:00:00Z") }
            jsonPath("$.nextCursor") { value(null) }
            jsonPath("$.hasNext") { value(false) }
        }
    }

    @Test
    fun `다른 사용자의 운동장으로 경기를 저장하면 거부된다`() {
        val ownerToken = jwtTokenProvider.createAccessToken(userId = 4L)
        val otherToken = jwtTokenProvider.createAccessToken(userId = 5L)
        val venueId = createVenue(ownerToken, name = "남의 운동장")

        mockMvc.put("/matches/44444444-4444-4444-4444-444444444444") {
            header(HttpHeaders.AUTHORIZATION, "Bearer $otherToken")
            contentType = MediaType.APPLICATION_JSON
            content = matchJson(venueId = venueId)
        }.andExpect {
            status { isForbidden() }
            jsonPath("$.code") { value("VENUE_NOT_OWNED") }
        }
    }

    @Test
    fun `없는 운동장으로 경기를 저장하면 실패한다`() {
        val accessToken = jwtTokenProvider.createAccessToken(userId = 6L)

        mockMvc.put("/matches/55555555-5555-5555-5555-555555555555") {
            header(HttpHeaders.AUTHORIZATION, "Bearer $accessToken")
            contentType = MediaType.APPLICATION_JSON
            content = matchJson(venueId = 999999L)
        }.andExpect {
            status { isNotFound() }
            jsonPath("$.code") { value("VENUE_NOT_FOUND") }
        }
    }

    @Test
    fun `로그인 사용자는 본인 경기를 삭제한다`() {
        val accessToken = jwtTokenProvider.createAccessToken(userId = 7L)
        val venueId = createVenue(accessToken, name = "삭제 운동장")
        val clientMatchId = "77777777-7777-7777-7777-777777777777"

        val matchId = saveMatchAndReturnId(accessToken, clientMatchId, venueId)

        mockMvc.delete("/matches/$matchId") {
            header(HttpHeaders.AUTHORIZATION, "Bearer $accessToken")
        }.andExpect {
            status { isNoContent() }
        }

        mockMvc.get("/matches/$matchId") {
            header(HttpHeaders.AUTHORIZATION, "Bearer $accessToken")
        }.andExpect {
            status { isNotFound() }
            jsonPath("$.code") { value("MATCH_NOT_FOUND") }
        }
    }

    @Test
    fun `다른 사용자의 경기를 삭제하면 거부된다`() {
        val ownerToken = jwtTokenProvider.createAccessToken(userId = 8L)
        val otherToken = jwtTokenProvider.createAccessToken(userId = 9L)
        val venueId = createVenue(ownerToken, name = "삭제 권한 운동장")
        val matchId = saveMatchAndReturnId(ownerToken, "88888888-8888-8888-8888-888888888888", venueId)

        mockMvc.delete("/matches/$matchId") {
            header(HttpHeaders.AUTHORIZATION, "Bearer $otherToken")
        }.andExpect {
            status { isForbidden() }
            jsonPath("$.code") { value("MATCH_NOT_OWNED") }
        }
    }

    @Test
    fun `accepted 친구의 경기 목록과 상세를 조회한다`() {
        val viewer = createUser("친구경기조회자")
        val friend = createUser("친구경기소유자")
        val viewerToken = jwtTokenProvider.createAccessToken(viewer.id)
        val friendToken = jwtTokenProvider.createAccessToken(friend.id)
        saveAcceptedFriendship(viewer.id, friend.id)
        val venueId = createVenue(friendToken, name = "친구경기장")
        val matchId = saveMatchAndReturnId(friendToken, "99999999-9999-9999-9999-999999999991", venueId)

        mockMvc.get("/users/${friend.id}/matches") {
            header(HttpHeaders.AUTHORIZATION, "Bearer $viewerToken")
        }.andExpect {
            status { isOk() }
            jsonPath("$.content[0].id") { value(matchId) }
            jsonPath("$.content[0].opponent") { value("OO FC") }
        }

        mockMvc.get("/users/${friend.id}/matches/$matchId") {
            header(HttpHeaders.AUTHORIZATION, "Bearer $viewerToken")
        }.andExpect {
            status { isOk() }
            jsonPath("$.id") { value(matchId) }
            jsonPath("$.quarters.length()") { value(1) }
        }
    }

    @Test
    fun `accepted 친구가 아니면 친구 경기 목록을 조회할 수 없다`() {
        val viewer = createUser("비친구조회자")
        val other = createUser("비친구대상")
        val viewerToken = jwtTokenProvider.createAccessToken(viewer.id)

        mockMvc.get("/users/${other.id}/matches") {
            header(HttpHeaders.AUTHORIZATION, "Bearer $viewerToken")
        }.andExpect {
            status { isForbidden() }
            jsonPath("$.code") { value("FRIEND_UNAUTHORIZED") }
        }
    }

    @Test
    fun `친구 관계여도 다른 사용자의 matchId 상세는 조회할 수 없다`() {
        val viewer = createUser("친구상세조회자")
        val friend = createUser("친구상세대상")
        val outsider = createUser("친구상세외부자")
        val viewerToken = jwtTokenProvider.createAccessToken(viewer.id)
        val outsiderToken = jwtTokenProvider.createAccessToken(outsider.id)
        saveAcceptedFriendship(viewer.id, friend.id)
        val venueId = createVenue(outsiderToken, name = "외부자경기장")
        val matchId = saveMatchAndReturnId(outsiderToken, "99999999-9999-9999-9999-999999999992", venueId)

        mockMvc.get("/users/${friend.id}/matches/$matchId") {
            header(HttpHeaders.AUTHORIZATION, "Bearer $viewerToken")
        }.andExpect {
            status { isNotFound() }
            jsonPath("$.code") { value("MATCH_NOT_FOUND") }
        }
    }

    @Test
    fun `teamGoals 가 opponentGoals 보다 크면 result 는 WIN 으로 자동 derive 된다`() {
        val accessToken = jwtTokenProvider.createAccessToken(userId = 101L)
        val venueId = createVenue(accessToken, name = "팀골WIN운동장")

        mockMvc.put("/matches/aaaaaaa1-0000-0000-0000-000000000001") {
            header(HttpHeaders.AUTHORIZATION, "Bearer $accessToken")
            contentType = MediaType.APPLICATION_JSON
            content = matchJsonWithTeamGoals(venueId = venueId, goals = 1, teamGoals = 3, opponentGoals = 2)
        }.andExpect {
            status { isCreated() }
            jsonPath("$.result") { value("WIN") }
            jsonPath("$.teamGoals") { value(3) }
            jsonPath("$.opponentGoals") { value(2) }
        }
    }

    @Test
    fun `teamGoals 와 opponentGoals 가 같으면 result 는 DRAW 로 derive 된다`() {
        val accessToken = jwtTokenProvider.createAccessToken(userId = 102L)
        val venueId = createVenue(accessToken, name = "팀골DRAW운동장")

        mockMvc.put("/matches/aaaaaaa2-0000-0000-0000-000000000002") {
            header(HttpHeaders.AUTHORIZATION, "Bearer $accessToken")
            contentType = MediaType.APPLICATION_JSON
            content = matchJsonWithTeamGoals(venueId = venueId, goals = 0, teamGoals = 1, opponentGoals = 1)
        }.andExpect {
            status { isCreated() }
            jsonPath("$.result") { value("DRAW") }
            jsonPath("$.teamGoals") { value(1) }
            jsonPath("$.opponentGoals") { value(1) }
        }
    }

    @Test
    fun `teamGoals 가 opponentGoals 보다 작으면 result 는 LOSS 로 derive 된다`() {
        val accessToken = jwtTokenProvider.createAccessToken(userId = 103L)
        val venueId = createVenue(accessToken, name = "팀골LOSS운동장")

        mockMvc.put("/matches/aaaaaaa3-0000-0000-0000-000000000003") {
            header(HttpHeaders.AUTHORIZATION, "Bearer $accessToken")
            contentType = MediaType.APPLICATION_JSON
            content = matchJsonWithTeamGoals(venueId = venueId, goals = 0, teamGoals = 0, opponentGoals = 2)
        }.andExpect {
            status { isCreated() }
            jsonPath("$.result") { value("LOSS") }
            jsonPath("$.teamGoals") { value(0) }
            jsonPath("$.opponentGoals") { value(2) }
        }
    }

    @Test
    fun `teamGoals 와 opponentGoals 모두 null 이면 result 도 null 로 저장된다`() {
        val accessToken = jwtTokenProvider.createAccessToken(userId = 104L)
        val venueId = createVenue(accessToken, name = "팀골NULL운동장")

        mockMvc.put("/matches/aaaaaaa4-0000-0000-0000-000000000004") {
            header(HttpHeaders.AUTHORIZATION, "Bearer $accessToken")
            contentType = MediaType.APPLICATION_JSON
            content = matchJsonWithTeamGoals(venueId = venueId, goals = 0, teamGoals = null, opponentGoals = null)
        }.andExpect {
            status { isCreated() }
            jsonPath("$.result") { value(null) }
            jsonPath("$.teamGoals") { value(null) }
            jsonPath("$.opponentGoals") { value(null) }
        }
    }

    @Test
    fun `teamGoals 가 goals 보다 작으면 400 으로 거부한다`() {
        val accessToken = jwtTokenProvider.createAccessToken(userId = 105L)
        val venueId = createVenue(accessToken, name = "팀골검증운동장")

        mockMvc.put("/matches/aaaaaaa5-0000-0000-0000-000000000005") {
            header(HttpHeaders.AUTHORIZATION, "Bearer $accessToken")
            contentType = MediaType.APPLICATION_JSON
            content = matchJsonWithTeamGoals(venueId = venueId, goals = 2, teamGoals = 1, opponentGoals = 0)
        }.andExpect {
            status { isBadRequest() }
            jsonPath("$.message") { value(org.hamcrest.Matchers.containsString("팀 전체 골")) }
        }
    }

    @Test
    fun `client 가 result 필드를 보내도 백엔드는 무시하고 derive 값으로 저장한다`() {
        val accessToken = jwtTokenProvider.createAccessToken(userId = 106L)
        val venueId = createVenue(accessToken, name = "result무시운동장")
        // 명시적으로 result=LOSS 를 보냈지만 teamGoals(3) > opponentGoals(2) 이므로 derive WIN 이 우선
        val body = """
            {
              "venueId": $venueId,
              "playedAt": "2026-05-27T09:00:00Z",
              "opponent": "OO FC",
              "result": "LOSS",
              "position": "MF",
              "goals": 1,
              "assists": 0,
              "teamGoals": 3,
              "opponentGoals": 2,
              "quarters": [
                {
                  "quarterNumber": 1,
                  "healthKitWorkoutId": "hk-uuid-1",
                  "startedAt": "2026-05-27T09:00:00Z",
                  "endedAt": "2026-05-27T09:15:00Z"
                }
              ]
            }
        """.trimIndent()

        mockMvc.put("/matches/aaaaaaa6-0000-0000-0000-000000000006") {
            header(HttpHeaders.AUTHORIZATION, "Bearer $accessToken")
            contentType = MediaType.APPLICATION_JSON
            content = body
        }.andExpect {
            status { isCreated() }
            jsonPath("$.result") { value("WIN") }
            jsonPath("$.teamGoals") { value(3) }
        }
    }

    @Test
    fun `친구가 심박 숨김이면 친구 경기 상세의 심박 필드를 null로 마스킹한다`() {
        val viewer = createUser("심박조회자")
        val friend = createUser("심박숨김친구").also {
            it.hideHeartRate = true
            userRepository.save(it)
        }
        val viewerToken = jwtTokenProvider.createAccessToken(viewer.id)
        val friendToken = jwtTokenProvider.createAccessToken(friend.id)
        saveAcceptedFriendship(viewer.id, friend.id)
        val venueId = createVenue(friendToken, name = "심박숨김경기장")
        val matchId = saveMatchAndReturnId(friendToken, "99999999-9999-9999-9999-999999999993", venueId)

        mockMvc.get("/users/${friend.id}/matches/$matchId") {
            header(HttpHeaders.AUTHORIZATION, "Bearer $viewerToken")
        }.andExpect {
            status { isOk() }
            jsonPath("$.avgHeartRate") { value(null) }
            jsonPath("$.quarters[0].avgHeartRate") { value(null) }
            jsonPath("$.quarters[0].maxHeartRate") { value(null) }
        }
    }

    private fun createVenue(accessToken: String, name: String = "풍경운동장"): Long {
        val body = """
            {
              "name": "$name",
              "geoLat": 37.668100,
              "geoLng": 126.799200,
              "address": "경기 고양시 일산동구 풍동",
              "roadAddress": "경기 고양시 일산동구 숲속마을로",
              "provider": "kakao",
              "providerPlaceId": "$name"
            }
        """.trimIndent()

        val response = mockMvc.post("/venues") {
            header(HttpHeaders.AUTHORIZATION, "Bearer $accessToken")
            contentType = MediaType.APPLICATION_JSON
            content = body
        }.andReturn().response

        return Regex(""""id":(\d+)""").find(response.contentAsString)!!.groupValues[1].toLong()
    }

    private fun createUser(displayName: String): User {
        return userRepository.save(User.create(displayName = displayName, email = "$displayName@example.com"))
    }

    private fun saveAcceptedFriendship(userId: Long, targetUserId: Long) {
        val now = Instant.parse("2026-05-23T09:00:00Z")
        val friendship = Friendship.createPending(userId, targetUserId, now)
        friendship.accept(now)
        friendshipRepository.save(friendship)
    }

    private fun saveMatch(accessToken: String, clientMatchId: String, venueId: Long, playedAt: String) {
        mockMvc.put("/matches/$clientMatchId") {
            header(HttpHeaders.AUTHORIZATION, "Bearer $accessToken")
            contentType = MediaType.APPLICATION_JSON
            content = matchJson(venueId = venueId, playedAt = playedAt)
        }.andExpect {
            status { isCreated() }
        }
    }

    private fun saveMatchAndReturnId(accessToken: String, clientMatchId: String, venueId: Long): Long {
        val response = mockMvc.put("/matches/$clientMatchId") {
            header(HttpHeaders.AUTHORIZATION, "Bearer $accessToken")
            contentType = MediaType.APPLICATION_JSON
            content = matchJson(venueId = venueId)
        }.andReturn().response.contentAsString

        return Regex(""""id":(\d+)""").find(response)!!.groupValues[1].toLong()
    }

    private fun matchJsonWithTeamGoals(
        venueId: Long,
        goals: Int,
        teamGoals: Int?,
        opponentGoals: Int?,
        playedAt: String = "2026-05-27T09:00:00Z",
        quarterWorkoutId: String = "hk-uuid-1",
    ): String {
        val teamGoalsField = teamGoals?.toString() ?: "null"
        val opponentGoalsField = opponentGoals?.toString() ?: "null"
        return """
            {
              "venueId": $venueId,
              "playedAt": "$playedAt",
              "opponent": "OO FC",
              "position": "MF",
              "goals": $goals,
              "assists": 0,
              "teamGoals": $teamGoalsField,
              "opponentGoals": $opponentGoalsField,
              "quarters": [
                {
                  "quarterNumber": 1,
                  "healthKitWorkoutId": "$quarterWorkoutId",
                  "startedAt": "$playedAt",
                  "endedAt": "2026-05-27T09:15:00Z"
                }
              ]
            }
        """.trimIndent()
    }

    // result 는 백엔드가 teamGoals vs opponentGoals 로 derive — JSON 에 직접 보내지 않는다.
    // 기존 기대값 result=WIN 을 유지하기 위해 teamGoals=goals 이상, opponentGoals=0 으로 매핑.
    private fun matchJson(
        venueId: Long,
        playedAt: String = "2026-05-23T09:00:00Z",
        goals: Int = 1,
        quarterWorkoutId: String = "hk-uuid-1",
    ): String {
        val teamGoals = maxOf(goals, 1)
        return """
            {
              "venueId": $venueId,
              "playedAt": "$playedAt",
              "opponent": "OO FC",
              "position": "MF",
              "goals": $goals,
              "assists": 0,
              "teamGoals": $teamGoals,
              "opponentGoals": 0,
              "quarters": [
                {
                  "quarterNumber": 1,
                  "healthKitWorkoutId": "$quarterWorkoutId",
                  "startedAt": "$playedAt",
                  "endedAt": "2026-05-23T09:15:00Z"
                }
              ]
            }
        """.trimIndent()
    }
}
