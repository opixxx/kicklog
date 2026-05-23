package com.opixxx.kicklog.match

import com.opixxx.kicklog.common.security.JwtTokenProvider
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

@SpringBootTest
@AutoConfigureMockMvc
@ActiveProfiles("test")
class MatchAcceptanceTest {

    @Autowired
    private lateinit var mockMvc: MockMvc

    @Autowired
    private lateinit var jwtTokenProvider: JwtTokenProvider

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

    private fun matchJson(
        venueId: Long,
        playedAt: String = "2026-05-23T09:00:00Z",
        goals: Int = 1,
        quarterWorkoutId: String = "hk-uuid-1",
    ): String {
        return """
            {
              "venueId": $venueId,
              "playedAt": "$playedAt",
              "opponent": "OO FC",
              "result": "WIN",
              "position": "MF",
              "goals": $goals,
              "assists": 0,
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
