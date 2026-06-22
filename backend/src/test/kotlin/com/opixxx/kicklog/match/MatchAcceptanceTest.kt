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
    fun `이미 저장된 2쿼터 경기를 재계산 PUT 하면 200 과 함께 모든 쿼터 지표가 갱신된다`() {
        // 회귀: 기존 경기를 다시 PUT(지표 재계산/재라벨링)할 때 quarter_workouts (match_id, quarter_number)
        // unique 제약 위반(500)으로 저장이 반영되지 않던 버그. 2쿼터 이상에서만 드러난다.
        val accessToken = jwtTokenProvider.createAccessToken(userId = 201L)
        val venueId = createVenue(accessToken, name = "재계산운동장")
        val clientMatchId = "bbbbbbb1-0000-0000-0000-000000000001"

        // 1) 최초 저장 — 2쿼터, distanceM = 0 (import 지연으로 0 저장된 상황 재현)
        mockMvc.put("/matches/$clientMatchId") {
            header(HttpHeaders.AUTHORIZATION, "Bearer $accessToken")
            contentType = MediaType.APPLICATION_JSON
            content = twoQuarterMatchJson(venueId = venueId, q1Distance = 0, q2Distance = 0)
        }.andExpect {
            status { isCreated() }
            jsonPath("$.quarters.length()") { value(2) }
        }

        // 2) 재계산 PUT — 같은 2쿼터를 실제 지표로 갱신 → 200 + 지표 반영 (기존엔 여기서 500)
        mockMvc.put("/matches/$clientMatchId") {
            header(HttpHeaders.AUTHORIZATION, "Bearer $accessToken")
            contentType = MediaType.APPLICATION_JSON
            content = twoQuarterMatchJson(venueId = venueId, q1Distance = 1500, q2Distance = 1800)
        }.andExpect {
            status { isOk() }
            jsonPath("$.quarters.length()") { value(2) }
            jsonPath("$.quarters[0].distanceM") { value(1500) }
            jsonPath("$.quarters[1].distanceM") { value(1800) }
        }

        // 3) 재조회로 영속화 확인 (0 으로 되돌아가지 않음)
        mockMvc.get("/matches/by-client-id/$clientMatchId") {
            header(HttpHeaders.AUTHORIZATION, "Bearer $accessToken")
        }.andExpect {
            status { isOk() }
            jsonPath("$.quarters[0].distanceM") { value(1500) }
            jsonPath("$.quarters[1].distanceM") { value(1800) }
        }
    }

    @Test
    fun `쿼터 번호 set 을 부분 교체하여 재PUT 하면 삭제·갱신·추가가 한 번에 반영된다`() {
        // in-place 동기화의 핵심 위험 경로: 한 PUT 안에서 DELETE(Q1) + UPDATE(Q2) + INSERT(Q3)가
        // 같은 flush 에 묶인다. quarter_number 재사용이 없으므로 unique 충돌 없이 통과해야 한다.
        val accessToken = jwtTokenProvider.createAccessToken(userId = 203L)
        val venueId = createVenue(accessToken, name = "부분교체운동장")
        val clientMatchId = "bbbbbbb3-0000-0000-0000-000000000003"

        // 1) Q1, Q2 저장
        mockMvc.put("/matches/$clientMatchId") {
            header(HttpHeaders.AUTHORIZATION, "Bearer $accessToken")
            contentType = MediaType.APPLICATION_JSON
            content = twoQuarterMatchJson(venueId = venueId, q1Distance = 1000, q2Distance = 1000)
        }.andExpect { status { isCreated() } }

        // 2) Q1 제거 + Q2 갱신(거리·심박 동시) + Q3 신규 → 200
        val body = """
            {
              "venueId": $venueId,
              "playedAt": "2026-05-23T09:00:00Z",
              "opponent": "OO FC",
              "position": "MF",
              "goals": 1,
              "assists": 0,
              "teamGoals": 1,
              "opponentGoals": 0,
              "quarters": [
                {
                  "quarterNumber": 2,
                  "healthKitWorkoutId": "hk-q2",
                  "startedAt": "2026-05-23T09:20:00Z",
                  "endedAt": "2026-05-23T09:35:00Z",
                  "distanceM": 2222,
                  "avgHeartRate": 155
                },
                {
                  "quarterNumber": 3,
                  "healthKitWorkoutId": "hk-q3",
                  "startedAt": "2026-05-23T09:40:00Z",
                  "endedAt": "2026-05-23T09:55:00Z",
                  "distanceM": 3333
                }
              ]
            }
        """.trimIndent()

        mockMvc.put("/matches/$clientMatchId") {
            header(HttpHeaders.AUTHORIZATION, "Bearer $accessToken")
            contentType = MediaType.APPLICATION_JSON
            content = body
        }.andExpect {
            status { isOk() }
            jsonPath("$.quarters.length()") { value(2) }
            jsonPath("$.quarters[0].quarterNumber") { value(2) }
            jsonPath("$.quarters[0].distanceM") { value(2222) }
            jsonPath("$.quarters[0].avgHeartRate") { value(155) }   // 지표(거리)뿐 아니라 시각·심박도 갱신되는지
            jsonPath("$.quarters[1].quarterNumber") { value(3) }
            jsonPath("$.quarters[1].distanceM") { value(3333) }
        }
    }

    @Test
    fun `2쿼터 경기를 1쿼터로 줄여 재PUT 하면 빠진 쿼터가 삭제된다`() {
        // orphanRemoval 경로 회귀 — in-place 갱신으로 바꿔도 빠진 쿼터는 정상 삭제되어야 한다.
        val accessToken = jwtTokenProvider.createAccessToken(userId = 202L)
        val venueId = createVenue(accessToken, name = "쿼터축소운동장")
        val clientMatchId = "bbbbbbb2-0000-0000-0000-000000000002"

        mockMvc.put("/matches/$clientMatchId") {
            header(HttpHeaders.AUTHORIZATION, "Bearer $accessToken")
            contentType = MediaType.APPLICATION_JSON
            content = twoQuarterMatchJson(venueId = venueId, q1Distance = 1000, q2Distance = 1000)
        }.andExpect {
            status { isCreated() }
            jsonPath("$.quarters.length()") { value(2) }
        }

        mockMvc.put("/matches/$clientMatchId") {
            header(HttpHeaders.AUTHORIZATION, "Bearer $accessToken")
            contentType = MediaType.APPLICATION_JSON
            content = matchJson(venueId = venueId, quarterWorkoutId = "hk-q1-only")
        }.andExpect {
            status { isOk() }
            jsonPath("$.quarters.length()") { value(1) }
            jsonPath("$.quarters[0].quarterNumber") { value(1) }
            jsonPath("$.quarters[0].healthKitWorkoutId") { value("hk-q1-only") }
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
    fun `친구 경기 상세의 avgHeartRate 와 quarter 심박은 마스킹 없이 평문으로 노출된다`() {
        // EXEC_PLAN 2026-05-28 p0-cleanup — hideHeartRate 정책 폐기 후 친구는 모든 지표를 본다.
        val viewer = createUser("심박평문조회자")
        val friend = createUser("심박평문친구")
        val viewerToken = jwtTokenProvider.createAccessToken(viewer.id)
        val friendToken = jwtTokenProvider.createAccessToken(friend.id)
        saveAcceptedFriendship(viewer.id, friend.id)
        val venueId = createVenue(friendToken, name = "심박평문경기장")
        val matchId = saveMatchAndReturnId(friendToken, "99999999-9999-9999-9999-999999999994", venueId)

        mockMvc.get("/users/${friend.id}/matches/$matchId") {
            header(HttpHeaders.AUTHORIZATION, "Bearer $viewerToken")
        }.andExpect {
            status { isOk() }
            // matchJson 기본값은 avgHeartRate 미입력(=0). 평문 노출이므로 0 (≠ null).
            jsonPath("$.avgHeartRate") { value(0) }
            jsonPath("$.quarters[0].avgHeartRate") { value(0) }
            jsonPath("$.quarters[0].maxHeartRate") { value(0) }
        }
    }

    @Test
    fun `친구 경기 목록의 avgHeartRate 도 마스킹 없이 평문 노출된다`() {
        // 친구 경기 목록 endpoint 역시 hideHeartRate 정책 폐기 적용.
        val viewer = createUser("목록심박조회자")
        val friend = createUser("목록심박친구")
        val viewerToken = jwtTokenProvider.createAccessToken(viewer.id)
        val friendToken = jwtTokenProvider.createAccessToken(friend.id)
        saveAcceptedFriendship(viewer.id, friend.id)
        val venueId = createVenue(friendToken, name = "목록심박경기장")
        saveMatchAndReturnId(friendToken, "99999999-9999-9999-9999-999999999995", venueId)

        mockMvc.get("/users/${friend.id}/matches") {
            header(HttpHeaders.AUTHORIZATION, "Bearer $viewerToken")
        }.andExpect {
            status { isOk() }
            jsonPath("$.content[0].avgHeartRate") { value(0) }
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

    // 2쿼터 경기 JSON — 재PUT 시 unique 제약 충돌 회귀 검증용. 쿼터별 distanceM 을 지정해 갱신을 확인한다.
    private fun twoQuarterMatchJson(
        venueId: Long,
        q1Distance: Int,
        q2Distance: Int,
        playedAt: String = "2026-05-23T09:00:00Z",
    ): String {
        return """
            {
              "venueId": $venueId,
              "playedAt": "$playedAt",
              "opponent": "OO FC",
              "position": "MF",
              "goals": 1,
              "assists": 0,
              "teamGoals": 1,
              "opponentGoals": 0,
              "quarters": [
                {
                  "quarterNumber": 1,
                  "healthKitWorkoutId": "hk-q1",
                  "startedAt": "$playedAt",
                  "endedAt": "2026-05-23T09:15:00Z",
                  "distanceM": $q1Distance
                },
                {
                  "quarterNumber": 2,
                  "healthKitWorkoutId": "hk-q2",
                  "startedAt": "2026-05-23T09:20:00Z",
                  "endedAt": "2026-05-23T09:35:00Z",
                  "distanceM": $q2Distance
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
